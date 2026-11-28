// Moment 原生阶段 2 首版：SwiftUI + moment-ffi（Rust Core）。
// 列表（日期分组/搜索/置顶/删除/新建）+ 块编辑器（段落/
// 标题/todo 可编辑、长按拖拽重排、块增删、自动存回）。
// 现状（0.5.0）：列表/搜索/编辑/行内标记（含 link 段 url
// 保真）/图片/gallery/卡片/视频/附件/imgText 块、块类型
// 切换、ZIP 互通、Diag lite 均已入。余：双栏宽屏形态、
// 斜杠菜单。
// 工具链口径：@State 的 $ 投影不可用，状态一律走
// ObservableObject + 显式 Binding（见 spike/SPIKE.md）。
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import WebKit
import WebKit
import AVKit
import PhotosUI
import CoreLocation

enum Clock {
    static let t0 = ProcessInfo.processInfo.systemUptime
    static func ms() -> Int {
        Int((ProcessInfo.processInfo.systemUptime - t0) * 1000)
    }
    // 共享 formatter（0.9.48，治 S1 单价）：ISO8601
    // DateFormatter 的构造是已知贵操作，此前 isoNow/
    // parseISO 每次调用新建一个——列表归组每趟对全
    // 库逐篇付一遍构造价。两形态（带/不带小数秒）各
    // 预建一个共享实例；formatter 本身非线程安全，
    // 全部访问经锁串行（解析是短临界区）。解析结果
    // 按篇缓存未取：MemoItem 为值类型、getter 不可
    // memoize，构造期缓存需显式 init 手术改造全部加
    // 载路径——共享 formatter 已除去构造价这一主项，
    // 余下纯解析为 µs 级，二阶收益不值当（报告方向
    // 2 的取舍）。
    private static let isoLock = NSLock()
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime,
                           .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func isoNow() -> String {
        isoLock.lock()
        defer { isoLock.unlock() }
        return isoFull.string(from: Date())
    }
    static func parseISO(_ s: String) -> Date? {
        isoLock.lock()
        defer { isoLock.unlock() }
        return isoFull.date(from: s)
            ?? isoPlain.date(from: s)
    }
}

// ── 块状态：包着原始节点字典，编辑只改 text/checked ──
final class BlockState: ObservableObject, Identifiable {
    let id: String
    var node: [String: Any]
    @Published var text: String
    @Published var checked: Bool
    /// 行盒高（单点口径，fix_drag_pickup_quote_face
    /// 定案）：BlockRow 行盒 GeometryReader 全块型
    /// 无条件喂入——含行竖向 padding 与块内非文
    /// 构件（标题顶距/提示标题行）的整槽高。全仓
    /// 消费方同此口径：拖拽 pitch 累加（commitDrag/
    /// dragShift 的 height + 6）、菜单层贴面定位
    /// （frameMinY + height + 8）、liftScale 纵轴
    /// 输入、UITest rowFrame。旧双喂（文本块由
    /// UITextView 内容高喂入）令含 padding 块型
    /// （quote/callout/codeBlock/heading）整列少
    /// 算 padding 量、face==row 断言逐值差 20，
    /// 已废。
    @Published var height: CGFloat = 24
    /// UITextView 内容高（仅 BlockTextView.
    /// sizeThatFits 自守卫记录：同签名重复量测的
    /// 写抑制判据）：不喂 height——内容高 ≠ 行盒
    /// 高（差 = 行 padding + 非文构件），混喂即
    /// 上条双喂回潮。
    var contentH: CGFloat = 0
    /// 块顶在 editorScroll 坐标中的位置（斜杠面板锚定
    /// 用；非 Published——滚动每帧变化不触发重演算，
    /// 面板打开时读当前值）。
    var frameMinY: CGFloat = 0
    /// 行实测宽（非 Published；拾起双轴缩放的宽度基
    /// 准，与 height 同路由 GeometryReader 回报）。
    var rowW: CGFloat = 0
    /// 块左缘在 editorScroll 坐标中的位置（面板横向
    /// 锚栏用；independent 右栏为该栏自身空间坐标）。
    var frameMinX: CGFloat = 0
    /// 卡面量测通道（U2 地基，矩阵 §6.1）：卡面在
    /// editorScroll 坐标中的帧（minX/minY/W/H）与
    /// 面半径派生回读。回报分工：行级面块型（面 ≡
    /// 行槽）由 BlockRow 行盒 GeometryReader 与
    /// frameMinX 同点回报；image/gallery 的面在行
    /// 内分支（内缩后卡槽）由分支面 GeometryReader
    /// 回报。非 Published（量测面不触发重演算，与
    /// frameMinX 同口径）。未回报判据：faceW == 0
    /// （帧未到）；faceRadius 哨兵：−2 = 未回报、
    /// −1 = 面在子视图（image/gallery，半径在子视
    /// 图 LiftFrame 调用点、无行级单值）、0 = 无面
    /// （纯文本行）、>0 = 面半径派生值。探针据哨兵
    /// 回 surface_missing 语义，不拿旧值充数。
    var faceMinX: CGFloat = 0
    var faceMinY: CGFloat = 0
    var faceW: CGFloat = 0
    var faceH: CGFloat = 0
    var faceRadius: CGFloat = -2
    @Published var nodeVersion = 0
    /// 图文块「编辑」信号（长按菜单 → ImgTextBlockView 开
    /// 全文编辑面板）。
    @Published var imgTextEditSignal = 0
    /// MD 预览缓存（按源码文本键，文本变即失效）：分类
    /// 标识与解析树（core 同一解析器产物）。
    var mdCacheText: String?
    var mdCacheKind = "none"
    var mdCacheBlocks: [Any] = []
    /// R10：空解析结果也是有效缓存（此前以数组非空兼
    /// 任命中判定，空结果每次重解析）。
    var mdCacheDone = false
    /// 缓存失效单点（fix_md_cache_stale）：解析树与
    /// 完成标记必须同点作废。不变量：mdCacheDone
    /// == true ⟹ mdCacheBlocks 是 mdCacheText 的解
    /// 析树。只清树不复位 done，后继 mdBlocks 会把
    /// 空树当有效缓存命中返回、预览恒落原文兜底。
    /// 一切失效只许经此函数，不许散点直写两字段。
    func invalidateMdCache() {
        mdCacheBlocks = []
        mdCacheDone = false
    }
    let originalText: String

    var type: String { node["type"] as? String ?? "paragraph" }
    var isText: Bool {
        type == "paragraph" || type == "heading" || type == "todo"
            || type == "quote" || type == "callout"
            || type == "codeBlock"
    }
    var isList: Bool {
        type == "bulleted-list" || type == "numbered-list"
    }
    /// 列表块的子项状态（list-item 节点逐个成状态）。
    var itemStates: [BlockState] = []
    /// 列表项内的嵌套列表（list-item 的子列表块）。
    var nestedList: BlockState?
    static func isListNode(_ n: [String: Any]) -> Bool {
        let t = n["type"] as? String ?? ""
        return t == "bulleted-list" || t == "numbered-list"
    }
    /// 结构原子性（卡片防误触机制的分类单点，
    /// impl_card_guard_unify）：合并/选中面按原子块
    /// 对待——非文本块恒是；文本块中仅卡片机制成员
    /// （cardMenuTypes，当前为 codeBlock：源码态字
    /// 面内容、结构溶解即内容损毁）入列。纯文本流
    /// 块（段落/标题/待办/引用/提示与列表项）不入：
    /// 跨块合并即其编辑模型本身。isText 回答「内容
    /// 可否打字编辑」，本谓词回答「结构可否被键盘
    /// 合并/溶解」，两问分立、勿混用。
    var isStructuralAtomic: Bool {
        !isText || EditorModel.cardMenuTypes.contains(type)
    }
    var fileId: String? {
        (node["attrs"] as? [String: Any])?["fileId"] as? String
    }
    /// 卡片面型（补丁债偿还批二 A-2）：判别收口
    /// CardFace.derive 单点（MomentBlockKind），
    /// 本适配只按呈现侧口径喂字段——status/url/
    /// title 取 node 顶层与 meta（CardBlockView
    /// 同源读法）、fileCount 与 AttachmentBlock
    /// View.files 同口径（items 中带 fileId 者
    /// 计数、无 items 时 attrs.fileId 兜底一
    /// 件）。呈现分发/本与拾起面三方共消费。
    var cardFace: CardFace {
        let attrs = node["attrs"] as? [String: Any]
        var fileCount = 0
        if let items = attrs?["items"]
            as? [[String: Any]] {
            fileCount = items.filter {
                ($0["fileId"] as? String) != nil
            }.count
        } else if fileId != nil {
            fileCount = 1
        }
        return CardFace.derive(CardFaceInput(
            type: type,
            status: node["status"] as? String ?? "",
            url: node["url"] as? String ?? "",
            title: (node["meta"] as? [String: Any])?[
                "title"] as? String ?? "",
            hasFileId: fileId != nil,
            nodeImage: (node["image"] as? Bool) == true,
            fileCount: fileCount))
    }
    var imageURL: String? {
        let attrs = node["attrs"] as? [String: Any]
        return attrs?["url"] as? String ?? attrs?["src"] as? String
    }
    var level: Int {
        (node["attrs"] as? [String: Any])?["level"] as? Int ?? 2
    }

    var calloutVariant: String {
        var v = node["calloutType"] as? String
        if v == nil,
           let attrs = node["attrs"] as? [String: Any] {
            v = attrs["calloutType"] as? String
        }
        let l = (v ?? "note").lowercased()
        return ["note", "warning", "tip", "important",
                "caution"].contains(l) ? l : "note"
    }
    var calloutTitle: String {
        switch calloutVariant {
        case "tip": return Lang.t("callout.tip")
        case "warning": return Lang.t("callout.warning")
        case "important": return Lang.t("callout.important")
        case "caution": return Lang.t("callout.caution")
        default: return Lang.t("callout.note")
        }
    }
    var calloutIcon: String {
        switch calloutVariant {
        case "tip": return "lightbulb.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "important": return "exclamationmark.circle.fill"
        case "caution": return "exclamationmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }
    var calloutAccent: Color { T.calloutAccent(calloutVariant) }
    var calloutBg: Color { T.calloutBg(calloutVariant) }

    init(node: [String: Any]) {
        self.node = node
        id = node["id"] as? String ?? UUID().uuidString
        let kids = node["children"] as? [[String: Any]] ?? []
        let joined = kids.compactMap {
            $0["text"] as? String
        }.joined()
        // 图文卡文本在 node.text/caption（core 口径），不在
        // children——读错源会让 Web 导入的图文卡显示为空。
        let ty = node["type"] as? String ?? ""
        if ty == "imgTextCard" || ty == "imageTextRow",
           let t = (node["text"] as? String)
            ?? (node["caption"] as? String) {
            text = t
            originalText = t
        } else {
            text = joined
            originalText = joined
        }
        runs = Self.runsFrom(children: kids)
        let attrs = node["attrs"] as? [String: Any]
        checked = attrs?["checked"] as? Bool ?? false
        if type == "heading" { height = 34 }
        // 列表结构：子项逐个成状态；列表项的 runs 只取
        // 行内子节点（嵌套列表单独成 nestedList 状态）。
        if isList {
            itemStates = kids.map { BlockState(node: $0) }
        } else if type == "list-item" {
            // runs/joined 天然只含行内子节点（嵌套列表节点
            // 无 text 键、非 link 型，解析时已跳过）。
            if let nested = kids.first(
                where: { Self.isListNode($0) }) {
                nestedList = BlockState(node: nested)
            }
        }
    }

    // 行内标记段：children 的文本节点序列（bool 标记键
    // bold/italic/underline/strikethrough/code）。link 子
    // 节点拍平成带下划线的文本段——未改动时走原样保留，
    // 改动后链接 url 丢失（已知口径差）。
    var runs: [[String: Any]] = []

    static func runsFrom(children: [[String: Any]])
        -> [[String: Any]] {
        var out: [[String: Any]] = []
        for c in children {
            if let t = c["text"] as? String {
                out.append(c)
            } else if c["type"] as? String == "link" {
                let lattrs = c["attrs"] as? [String: Any]
                let url = lattrs?["url"] as? String ?? ""
                let kids = c["children"] as? [[String: Any]] ?? []
                for k in kids {
                    if let t = k["text"] as? String {
                        var r = k
                        r["text"] = t
                        r["underline"] = true
                        r["_link"] = url
                        out.append(r)
                    }
                }
            }
        }
        return out
    }

    func flushedNode() -> [String: Any] {
        var n = node
        if isList {
            n["children"] = itemStates.map {
                $0.flushedNode()
            }
            return n
        }
        if type == "list-item" {
            let kids = node["children"] as? [[String: Any]]
                ?? []
            let inline = kids.filter {
                !Self.isListNode($0)
            }
            let original = Self.runsFrom(children: inline)
            var out: [[String: Any]] = Self.runsEqual(
                runs, original)
                ? inline : Self.childrenFrom(runs: runs)
            if let nl = nestedList {
                out.append(nl.flushedNode())
            } else if let orig = kids.first(
                where: { Self.isListNode($0) }) {
                out.append(orig)
            }
            n["children"] = out
            return n
        }
        guard isText else { return n }
        let original = Self.runsFrom(
            children: node["children"] as? [[String: Any]] ?? [])
        let runsChanged = !Self.runsEqual(runs, original)
        if runsChanged {
            n["children"] = Self.childrenFrom(runs: runs)
        }
        if type == "todo" {
            var attrs = n["attrs"] as? [String: Any] ?? [:]
            attrs["checked"] = checked
            n["attrs"] = attrs
        }
        return n
    }

    static func runsEqual(_ a: [[String: Any]],
                          _ b: [[String: Any]]) -> Bool {
        guard a.count == b.count else { return false }
        let keys = ["text", "bold", "italic", "underline",
                    "strikethrough", "code"]
        for i in a.indices {
            for k in keys {
                let av = a[i][k], bv = b[i][k]
                if k == "text" {
                    if (av as? String) != (bv as? String) {
                        return false
                    }
                } else if (av as? Bool ?? false)
                            != (bv as? Bool ?? false) {
                    return false
                }
            }
            if (a[i]["_link"] as? String)
                != (b[i]["_link"] as? String) {
                return false
            }
        }
        return true
    }

    /// runs → 模型 children：连续同 _link 段重组为 link
    /// 节点（attrs.url），其余段直出（剥 _link 私有键）。
    static func childrenFrom(runs: [[String: Any]])
        -> [[String: Any]] {
        var out: [[String: Any]] = []
        var i = 0
        while i < runs.count {
            let url = runs[i]["_link"] as? String
            if let url, !url.isEmpty {
                var kids: [[String: Any]] = []
                while i < runs.count
                        && (runs[i]["_link"] as? String) == url {
                    var r = runs[i]
                    r.removeValue(forKey: "_link")
                    kids.append(r)
                    i += 1
                }
                out.append([
                    "id": "l-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "link",
                    "attrs": ["url": url],
                    "children": kids,
                ])
            } else {
                var r = runs[i]
                r.removeValue(forKey: "_link")
                out.append(r)
                i += 1
            }
        }
        return out
    }
}

struct MemoItem: Identifiable {
    let id: String
    var title: String
    var pinned: Bool
    var createdAt: String
    var updatedAt: String
    var blocks: [BlockState]
    /// 原始备忘 JSON 全量：persist 时以此为底覆写已知键，
    /// bgColor/layout 等未建模字段原样带回（防编辑丢字段）。
    var raw: [String: Any] = [:]

    var bgColor: String? { raw["bgColor"] as? String }

    /// 待删标记（epoch 毫秒，Web deletedAt 键）：
    /// 在 = 处于删除撤销窗口内。
    var deletedAtMs: Int64? {
        (raw["deletedAt"] as? NSNumber)?.int64Value
    }

    var snippet: String {
        blocks.first(where: { $0.isText && !$0.text.isEmpty })?.text
            ?? ""
    }
    var updatedDate: Date { Clock.parseISO(updatedAt) ?? Date() }
    var createdDate: Date { Clock.parseISO(createdAt) ?? Date() }
}

/// 启动模式（S2）：判定在 Library.init 同步完成，
/// 根 ZStack 按此分流——.safe 时先渲染 RescueView、
/// 不构建 ListView（拆 0.9.43 式确定性启动死循环）。
enum BootMode: Equatable {
    case normal
    /// source: "streak"（连续未完成）| "ops"（热更
    /// 新指令 forceSafeMode，S13）| "bridge"（桥
    /// 布防一次性标记，M2 §7.3 接线批）| "watchdog"
    /// （看门狗浮条入口，S8）| "manual"（Diag 页手
    /// 动入口，救援完整性批——注记补齐，原注记漏
    /// 记 watchdog 一值已与代码漂移）。
    case safe(streak: Int, step: String, source: String)
}

// ── 库门面 ──────────────────────────────────────────
final class Library: ObservableObject {
    @Published var memos: [MemoItem] = []
    @Published var timing = "启动中…"
    @Published var searchHits: [String]? = nil
    /// 搜索命中集失效账（P3）：searchQuery 记最
    /// 近一次 search 的查询串（沉到 Library，收
    /// 口重算的前提）；searchHitsVersion 记命中
    /// 集算出时的 memosVersion。两者与 searchHits
    /// 在 search 内三同步（空查询同清），版本不等
    /// 即陈旧——由 refreshSearchHitsIfStale 在
    /// touchMemos 的版本 bump 后单点重算替换；
    /// 不得置 nil 失效（会塌搜索态呈现且与视图
    /// 侧 query 失同步）。
    private(set) var searchQuery: String?
    private(set) var searchHitsVersion: Int = -1
    @Published var loadFailed = false
    /// 冷启加载已收尾（成功或失败均置位；开屏消散与
    /// 就绪判定用，retryLoad 成功路径亦经 load 收口）。
    @Published var didLoad = false
    /// 启动模式（S2）：init 内判定前移的结果，根
    /// ZStack 按此分流（.safe 先渲染 RescueView）。
    @Published var bootMode: BootMode = .normal
    /// 本次启动判定实际消费的 OPS 指令集快照：
    /// 启动判定入口落点（判定与消费同
    /// 一份），桥 ops_get_effective 的 bootApplied
    /// 层回读源——与 fetch 后更新的 current 严格
    /// 区分（三层回读口径，方案 §6.5）。
    private(set) var bootAppliedOps = OpsDirectiveSet()
    /// 判定留痕：上次启动停步与连续未完成次数（判
    /// 定后值），RescueView 状态区消费。
    @Published var prevLaunchStep: String = ""
    @Published var prevLaunchStreak: Int = 0
    /// 判定留痕（LCH-02 根治批）：prevLaunchStreak
    /// 的锚步——判定点与上两字段同点赋值，救援页
    /// streak 行附带呈现（F2 呈现销账面）。
    @Published var prevLaunchStreakStep: String = ""
    /// streak == 1 时本次正常启动成功后提示一次
    /// （notice.launch_once），判定点只置标、load
    /// 成功后兑现（防与隔离 notice 互踩：空才写）。
    private var launchOnceNoticePending = false

    var bootIsSafe: Bool {
        if case .safe = bootMode { return true }
        return false
    }

    /// 库是否已打开（RescueView 的 ZIP 置灰判据；
    /// 只读句柄 R2 落地后只读态亦为 true）。
    var isDbOpen: Bool { lib != nil }

    /// 库打开模式（S4，R2）：只读态经门面拒写层
    /// 拦全部写路径（writeBlocked），呈现走只读横
    /// 幅；退出只读唯一路径 = 回安全模式页点「尝试
    /// 正常启动」（prepareNormalStart 复位）。
    enum OpenMode: Equatable {
        case none, readWrite, readOnly, readOnlyCopy
    }
    @Published var openMode: OpenMode = .none
    var isReadOnly: Bool {
        openMode == .readOnly || openMode == .readOnlyCopy
    }
    /// 进只读前的安全模式来源（横幅「进入救援」
    /// 回页时原样恢复 bootMode 的 safe 上下文）。
    private var rescueReturnSource = "streak"
    /// 看门狗（S8，R3）：冷启 12 秒未 didLoad 时置
    /// 真出救援浮条；didLoad 变真自动撤（根视图
    /// onChange 调 dismissWatchdog）。
    @Published var watchdogFired = false
    private var watchdogWork: DispatchWorkItem?
    /// 看门狗阈值单一定义点（S8，与 Web 救援层
    /// 12 秒口径对齐）。
    static let watchdogSeconds: Double = 12
    /// 待删集（Web U3 口径，二轮微差 16）：id →
    /// (备忘, 删除时刻 epoch 毫秒)。每篇独立打标落
    /// 盘、各自 8 秒到期真删，杀进程重开按标记再
    /// 水化；撤销条只跟最近一篇（pendingDeletion
    /// 派生）。旧实现为单槽——再删一篇即把前一篇
    /// 立即真删，与 Web 分叉。
    @Published var pendingDeletions:
        [String: (item: MemoItem, atMs: Int64)] = [:]
    private var deletionWorks:
        [String: DispatchWorkItem] = [:]

    /// 撤销条绑定面：最近一篇待删（Web pending_del
    /// 单 toast 口径——各篇到期各自独立，toast 与
    /// 撤销动作只对最近一篇）。
    var pendingDeletion: MemoItem? {
        pendingDeletions.values
            .max { $0.atMs < $1.atMs }?.item
    }

    static let undoWindowMs: Int64 = 8_000

    static func epochMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
    private var lib: MomentLibrary?
    private var firstFrameMs: Int?

    /// 首帧渲染时刻量测（ListView 探针调用）：与哨
    /// 兵「首帧」步痕（load 收尾面包屑）是两个口径，
    /// 区分见 load() 内步痕处注记（§5.1 b）。
    func markFirstFrame() {
        if firstFrameMs == nil { firstFrameMs = Clock.ms() }
    }

    var storeDir: String {
        let d = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("library").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }

    // ── 启动守卫（批 B + S1/S2 加密前移）──
    // 哨兵落 diag 域文件直写（LaunchSentinelStore）；
    // 判定在 init 同步执行（S2 前移——旧判定点埋在
    // load() 内、由 ListView.onAppear 触发，ListView
    // 构建不出来时判定根本不执行、提示永远看不到，
    // 是 0.9.43 确定性启动死循环的一环）。load 开始
    // 逐步落面包屑，成功收尾推进「会话中」不清标记
    // （G2 全会话口径）；打开库失败属已留痕的已知
    // 失败，清标记不计入连续次数。
    init() {
        judgePreviousLaunch()
        writeBootSnapshot()
        // 看门狗 arm 前移至此（救援完整性批，P2-2）：
        // 原 arm 只在 load() 起点、load() 由 ListView
        // .onAppear 触发——根视图构建期挂死时看门狗
        // 从未 arm、救援浮条永不出。init 末尾恒 arm
        // 使其独立于任何视图出现；load() 起点保留调
        // 用只作续期（armWatchdog 自带取消旧项）。
        armWatchdog()
        // MCP 桥启动接线（M1）：异步派发出 init 同
        // 步链（守 0.9.43 单例 init 纪律）；安全模
        // 式下亦启动——桥分发器转受限形态，
        // rescue_status 仍可回读。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            BridgeCoordinator.shared.start(library: self)
        }
    }

    private func launchMark(_ step: String) {
        // 读-改-写经哨兵串行 update（救援完整性批，
        // §5.2 c：无锁 RMW 交错可致步名回退/丢失）。
        if !LaunchSentinelStore.update({ s in
            s.busy = true
            s.step = step
        }) {
            // 留痕层自身失效也要留痕（S1）。
            DiagLog.shared.logOnce(
                "sentinel-write", .warn,
                "LAUNCH sentinel write failed")
        }
    }

    /// reload 内步点专用：只在哨兵处于加载态（未置
    /// 或加载步）时记——会话中触发的 reload（导入换
    /// 库）不得把步从「会话中」倒退回加载步，否则前
    /// 台死亡会被误判成启动死亡。
    private func loadStepMark(_ step: String) {
        let s = LaunchSentinelStore.load()
        if s.busy && !LaunchStep.isLoadStep(s.step) {
            return
        }
        launchMark(step)
    }

    private func launchDone() {
        // G2 全会话哨兵：加载完成不清标记，步骤推进
        // 到「会话中」——前台使用中进程终止（崩溃/
        // 被杀）时下次启动能留痕；正常退后台由
        // launchSuspend 清除，不误报。streak 与锚步
        // 一并清零（LCH-02 根治批：成功收尾 = 证据
        // 链断开，锚不残留）。
        LaunchSentinelStore.update {
            $0.streak = 0
            $0.streakStep = ""
        }
        launchMark(LaunchStep.session)
    }

    /// 场景标记（首页/编辑页/救援页出现时更新哨兵
    /// 步骤，崩溃留痕能定位到场景）。哨兵未置时不动。
    static func markScene(_ scene: String) {
        LaunchSentinelStore.update { s in
            guard s.busy else { return }
            s.step = scene
        }
    }

    /// 正常退后台：清哨兵（不算未收尾）。清标前
    /// 先把当前步名记为墓碑（LCH-02 根治批 F3，
    /// 与 launchResume 成保存/恢复对）：加载未完
    /// 即挂起、其后被后台回收时，下次判定凭墓碑
    /// 留痕（只记 warn、不计数，G2「退后台不误
    /// 报」守恒）；会话中挂起的墓碑为非加载步、
    /// 判定不消费、无痕。
    static func launchSuspend() {
        LaunchSentinelStore.update { s in
            s.suspendedStep = s.step
            s.busy = false
        }
    }

    /// 从后台回前台：续上哨兵（若已清）。步名恢
    /// 复挂起前步（LCH-02 根治批 F4）：加载中挂
    /// 起恢复回原加载步，在途 load 的步痕自然接
    /// 续、不再被伪造为「会话中」错分；无墓碑时
    /// 沿用「会话中」。恢复后清墓碑。
    static func launchResume() {
        LaunchSentinelStore.update { s in
            if !s.busy {
                s.busy = true
                s.step = s.suspendedStep.isEmpty
                    ? LaunchStep.session : s.suspendedStep
                s.suspendedStep = ""
            }
        }
    }

    private func launchFailed() {
        LaunchSentinelStore.update { $0.busy = false }
    }

    /// S6：救援动作跨启动留痕（RescueView 各动作调
    /// 用）：写哨兵 lastRescueAction，下次启动 LAUNCH
    /// 行尾附 lastRescue=。R3 起同步给快照环打标
    /// （S5 折行面：下次启动 RESCUE log 行的来源）。
    static func recordRescueAction(_ action: String) {
        LaunchSentinelStore.update { s in
            s.lastRescueAction = action
            s.lastRescueAt = Date().timeIntervalSince1970
        }
        RescueLogStore.markAction(action)
    }

    /// 状态快照环记账（S5，R3；init 内判定后调）：
    /// 先折上次启动快照上的救援动作标（有动作才记
    /// RESCUE log 行，纯快照静默——对位 Web W8），
    /// 再追加本次启动的判定点快照（计数面开库后由
    /// load 成功段 updateLatest 补写）。只读文件元
    /// 数据，不开库。
    private func writeBootSnapshot() {
        let drained = RescueLogStore.drainActionMarks()
        if !drained.actions.isEmpty {
            let last = drained.snap
            let desc = last.map {
                "mode=\($0.bootMode) db=\($0.dbBytes) "
                + "memos="
                + ($0.memoCount.map(String.init) ?? "-")
            } ?? "-"
            DiagLog.shared.log(.info,
                "RESCUE log actions="
                + drained.actions.joined(separator: ",")
                + " lastSnap=\(desc)")
        }
        DiagLog.shared.loadIfNeeded()
        let fm = FileManager.default
        let dbPath = storeDir + "/moment.db"
        let dbBytes = ((try? fm.attributesOfItem(
            atPath: dbPath))?[.size] as? NSNumber)?
            .int64Value ?? -1
        let fsAttrs = try? fm.attributesOfFileSystem(
            forPath: NSHomeDirectory())
        let diskFree = (fsAttrs?[.systemFreeSize]
            as? NSNumber)?.int64Value ?? -1
        let info = Bundle.main.infoDictionary
        let ver = (info?["CFBundleShortVersionString"]
            as? String ?? "?")
            + " (" + (info?["CFBundleVersion"]
                      as? String ?? "?") + ")"
        var mode = "normal"
        if case .safe = bootMode { mode = "safe" }
        RescueLogStore.append(RescueSnapshot(
            ts: Date().timeIntervalSince1970,
            appVersion: ver,
            systemVersion: ProcessInfo.processInfo
                .operatingSystemVersionString,
            prevStep: prevLaunchStep,
            streak: prevLaunchStreak,
            streakStep: prevLaunchStreakStep,
            bootMode: mode,
            dbBytes: dbBytes,
            diagToday: DiagLog.shared.today.count,
            diagArchives: DiagLog.shared.archives.count,
            diskFreeBytes: diskFree))
    }

    // ── 只读门面（S4，R2）──────────────────────
    // 只读态全部写入口首行经此拦截：记 READONLY
    // 行（同 kind 进程内只记一行）+ notice 告知，
    // 返回 true = 已拦截、调用方立即收手。写入口
    // 全集：persist / persistDeletionMark /
    // softRemove / undoDeletion /
    // commitPendingDeletion / remove（kind=
    // persist|delete）、种子（seed）、
    // putAttachment / setAvatar（attach）、导入
    // （import）。reload 内待删过期真删不经此（其
    // 在后台线程且语义为「仅隐藏」，单独记行）。
    private func writeBlocked(_ kind: String) -> Bool {
        guard isReadOnly else { return false }
        DiagLog.shared.logOnce(
            "readonly-block-\(kind)", .warn,
            "READONLY write-blocked kind=\(kind)")
        let text = Lang.t("rescue.readonly_write_blocked")
        if Thread.isMainThread {
            notice = text
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.notice = text
            }
        }
        return true
    }

    /// 只读态编辑入口守卫（救援完整性批，P2-5 用
    /// 户裁定落码）：UI 进编辑页的两条漏斗
    /// （ListView 的 openMemo / createAndOpen）在只
    /// 读态首行经此拦截——记行 + notice（文案与只
    /// 读横幅同源 rescue.readonly_banner），返回
    /// true = 已拦截、入口立即收手。消除「能进编
    /// 辑页打字、persist 时才被 writeBlocked 拦下、
    /// 编辑成果当场丢失」；门面拒写仍是最终兜底。
    func readonlyEntryBlocked(_ kind: String) -> Bool {
        guard isReadOnly else { return false }
        DiagLog.shared.logOnce(
            "readonly-entry-\(kind)", .warn,
            "READONLY entry-blocked kind=\(kind)")
        let text = Lang.t("rescue.readonly_banner")
        if Thread.isMainThread {
            notice = text
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.notice = text
            }
        }
        return true
    }

    /// 只读打开资料库（S4；RescueView 动作 3 调
    /// 用，动作记行在 RescueView 侧）：先直开只读
    /// 句柄，失败回退副本模式——db 三件套拷到 tmp
    /// 救援目录后以可写方式打开副本、门面按只读
    /// 对待（源库零触碰、副本可弃）。成功后进
    /// ListView 只读态（bootMode 切 .normal），退
    /// 出唯一路径 = 横幅回安全模式页点正常启动。
    func enterReadOnly() -> Bool {
        if case .safe(_, _, let source) = bootMode {
            rescueReturnSource = source
        }
        if openMode == .readOnlyCopy {
            removeReadOnlyCopyDir()
        }
        let dbPath = storeDir + "/moment.db"
        do {
            let ro = try MomentLibrary.openReadonly(
                path: dbPath)
            lib = ro
            openMode = .readOnly
            try reload(lib: ro)
            finishEnterReadOnly(mode: "direct")
            return true
        } catch {
            DiagLog.shared.log(.warn,
                "RESCUE readonly direct failed: \(error)")
        }
        do {
            let dir = readOnlyCopyDir()
            let fm = FileManager.default
            try? fm.removeItem(atPath: dir)
            try fm.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let src = dbPath + suffix
                if fm.fileExists(atPath: src) {
                    try fm.copyItem(
                        atPath: src,
                        toPath: dir + "/moment.db" + suffix)
                }
            }
            let cp = try MomentLibrary.open(
                path: dir + "/moment.db")
            lib = cp
            openMode = .readOnlyCopy
            try reload(lib: cp)
            finishEnterReadOnly(mode: "copy")
            return true
        } catch {
            DiagLog.shared.log(.error,
                "RESCUE readonly open fail err=\(error)")
            lib = nil
            openMode = .none
            return false
        }
    }

    private func finishEnterReadOnly(mode: String) {
        didLoad = true
        DiagLog.shared.log(.info,
            "RESCUE readonly open ok mode=\(mode)")
        DiagLog.shared.log(.info, "RESCUE exit to=readonly")
        bootMode = .normal
    }

    /// 只读副本目录名单点（救援完整性批）：救援页
    /// 清缓存须按此名跳过该目录（P2-4），名字只许
    /// 在此定义、消费方引用常量不散写字面。
    static let readOnlyCopyDirName = "moment-rescue-ro"

    /// 只读副本目录（tmp 域；退出/重进时可删）。
    private func readOnlyCopyDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                Self.readOnlyCopyDirName).path
    }

    private func removeReadOnlyCopyDir() {
        try? FileManager.default.removeItem(
            atPath: readOnlyCopyDir())
    }

    /// 横幅「进入救援」：回安全模式页（只读句柄
    /// 保留打开——救援页 ZIP 动作可继续用它导
    /// 出；正常启动时由 prepareNormalStart 复位）。
    func exitReadOnlyToRescue() {
        bootMode = .safe(streak: prevLaunchStreak,
                         step: prevLaunchStep,
                         source: rescueReturnSource)
    }

    /// 尝试正常启动前复位（RescueView.tryNormal
    /// 调用）：只读句柄关停、副本清掉、列表与待删
    /// 集清空——ListView 重建后 onAppear 以空列表
    /// 触发常规 load()。非只读态无操作。
    func prepareNormalStart() {
        guard isReadOnly else { return }
        if openMode == .readOnlyCopy {
            removeReadOnlyCopyDir()
        }
        lib = nil
        openMode = .none
        didLoad = false
        for w in deletionWorks.values { w.cancel() }
        deletionWorks.removeAll()
        pendingDeletions.removeAll()
        memos = []
        touchMemos()
    }

    // ── 看门狗（S8，R3）────────────────────────
    // 只管「活着但挂住」：Library.init 末尾恒 arm
    // （救援完整性批前移，P2-2——独立于任何视图出
    // 现，根视图构建期挂死亦有覆盖）、load() 起点
    // 调用只作续期（armWatchdog 自带取消旧项）；
    // didLoad（成功/失败两路）即取消；进程已死由
    // S2 哨兵在下次启动管。OPS 可点名禁用本步（热
    // 修面：浮条自身异常时远程关停，步名
    // OpsStep.watchdog 已在 MomentOps 登记）。
    private func armWatchdog() {
        watchdogWork?.cancel()
        watchdogWork = nil
        guard !bootIsSafe else { return }
        if OpsDirectives.cached().isDisabled(
            OpsStep.watchdog) {
            DiagLog.shared.logOnce(
                "ops-skip-watchdog", .info,
                "OPS skip step=" + OpsStep.watchdog)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.didLoad,
                  !self.bootIsSafe else { return }
            let step = LaunchSentinelStore.load().step
            DiagLog.shared.log(.error,
                "RESCUE watchdog fired step="
                + (step.isEmpty ? "-" : step))
            self.watchdogFired = true
        }
        watchdogWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.watchdogSeconds,
            execute: work)
    }

    private func cancelWatchdog() {
        watchdogWork?.cancel()
        watchdogWork = nil
    }

    /// 应用晚到就绪（didLoad 变真）时浮条自撤
    /// （根视图 onChange 调用，对位 Web 轮询自撤）。
    func dismissWatchdog() {
        if watchdogFired { watchdogFired = false }
    }

    /// 浮条「进入救援」：切安全模式页（来源标
    /// watchdog，RESCUE enter 行在此补记——判定点
    /// 的同名行只覆盖启动判定来源）。
    func enterRescueFromWatchdog() {
        watchdogFired = false
        let step = LaunchSentinelStore.load().step
        bootMode = .safe(streak: prevLaunchStreak,
                         step: step,
                         source: "watchdog")
        DiagLog.shared.log(.error,
            "RESCUE enter streak=\(prevLaunchStreak) "
            + "step=\(step.isEmpty ? "-" : step) "
            + "src=watchdog")
    }

    /// 手动进入救援（救援完整性批，P2-3）：Diag 页
    /// 入口调用——正常模式的手动通道，与 Web
    /// ?rescue=1 等价（App 能跑但劣化时用户可达救
    /// 援页，不必等 streak 攒满）。机制与看门狗入
    /// 口同：直接切 bootMode、根分流即时呈现
    /// RescueView；不写哨兵、不动数据。RESCUE
    /// enter 行在此补记（src=manual）。
    func enterRescueManually() {
        let step = LaunchSentinelStore.load().step
        bootMode = .safe(streak: prevLaunchStreak,
                         step: step,
                         source: "manual")
        DiagLog.shared.log(.error,
            "RESCUE enter streak=\(prevLaunchStreak) "
            + "step=\(step.isEmpty ? "-" : step) "
            + "src=manual")
    }

    /// 上次启动判定（S2，init 内同步执行）：停在加
    /// 载步 = 启动期死亡，streak 按锚步落盘（LCH-02
    /// 根治批：同一步复现才递增、异步换锚重计）；
    /// ≥2 进安全模式、≥3 沿用 notice、==1 本次成功
    /// 后提示一次。停在会话/场景/首帧步 = 前台终
    /// 止，warn 留痕不计数、永不触发安全模式。
    /// busy 已清但墓碑停在加载步 = 加载未完即挂起
    /// 后被回收，只留痕不计数（同批 F3）。判定同时读热更
    /// 新指令缓存（S13）：forceSafeMode 在位直接进
    /// 安全模式（来源标 ops）。第三路读桥布防一次
    /// 性标记（M2 §7.3）：判定点无条件消费恰一次，
    /// 前两路未定 safe 时由它定源（来源标
    /// bridge）。三路互不覆盖、任一成立即 safe。
    /// LAUNCH 行在此记（行文沿旧格式 + 附
    /// lastRescue）。
    private func judgePreviousLaunch() {
        bootAppliedOps = OpsDirectives.cached()
        var s = LaunchSentinelStore.load()
        if s.busy {
            let prevStep = s.step.isEmpty ? "?" : s.step
            let rescueSuffix = s.lastRescueAction.isEmpty
                ? "" : " lastRescue=\(s.lastRescueAction)"
            if LaunchStep.isLoadStep(prevStep) {
                // streak 同一步锚定（LCH-02 根治批
                // F1）：计数语义是「同一步确定性死
                // 亡循环」，故同一步复现才递增；停
                // 步与锚步不同 = 换锚重计为 1，旧锚
                // 证据作废——跨步散射的外部终止
                // （强杀/jetsam 各一）不再合并凑满
                // 阈值。落盘经串行 update（救援完整
                // 性批，§5.2 c；判定在 init 同步段、
                // 无并发写者，此处与全批同口径）。
                let sameStep = prevStep == s.streakStep
                let newStreak = sameStep
                    ? s.streak + 1 : 1
                LaunchSentinelStore.update {
                    $0.streak = newStreak
                    $0.streakStep = prevStep
                }
                prevLaunchStep = prevStep
                prevLaunchStreak = newStreak
                prevLaunchStreakStep = prevStep
                DiagLog.shared.log(.error,
                    "LAUNCH 上次启动未完成（停在步骤："
                    + "\(prevStep)），"
                    + (sameStep
                        ? "同一步连续第 \(newStreak) 次"
                        : "锚步变更、本步第 1 次")
                    + rescueSuffix
                    + "（注：同一步内强杀/系统回收与"
                    + "崩溃不可分，平台事实）")
                if newStreak >= 3 {
                    notice = Lang.tf(
                        "notice.launch_streak",
                        ["n": "\(newStreak)"])
                }
                if newStreak == 1 {
                    launchOnceNoticePending = true
                }
                if newStreak >= 2 {
                    bootMode = .safe(streak: newStreak,
                                     step: prevStep,
                                     source: "streak")
                }
            } else {
                DiagLog.shared.log(.warn,
                    "LAUNCH 上次会话未正常收尾（停在："
                    + "\(prevStep)），疑似前台崩溃或被系统终止"
                    + rescueSuffix)
            }
        } else if !s.suspendedStep.isEmpty,
                  LaunchStep.isLoadStep(s.suspendedStep) {
            // 墓碑留痕（LCH-02 根治批 F3）：上次加
            // 载未完即退后台、其后未回前台收尾
            // （挂起后被系统回收或直接冷启）——只
            // 记 warn 留痕并清墓碑，不计数、不定
            // bootMode：后台回收不是死亡证据（升
            // 级计数会反向制造误报面）。busy 在位
            // 时不走此支（resume 已清墓碑或已被
            // launchMark 链覆盖，防重复记行）。
            DiagLog.shared.log(.warn,
                "LAUNCH 上次加载未完成即退后台（停在："
                + "\(s.suspendedStep)），其后未回前台收尾"
                + "——后台回收不计数")
            LaunchSentinelStore.update {
                $0.suspendedStep = ""
            }
        }
        if bootMode == .normal,
           bootAppliedOps.forceSafeMode {
            bootMode = .safe(streak: prevLaunchStreak,
                             step: prevLaunchStep,
                             source: "ops")
        }
        // 第三路（桥布防，M2 §7.3 接线批）：diag
        // 域一次性标记——判定点无条件消费恰一次
        // （take 取走即清、随后转审计留痕），防
        // 「布防→进安全→尝试正常→下次启动被旧标
        // 记拽回」的循环布防；仅当前两路未定
        // safe 时由布防定源，已 safe 时只消费不
        // 改源（效果已达、标记不跨启动残留）。
        // 与 OPS forceSafeMode 分工：源头指令持
        // 续型（每启必读、改源头才放松），桥布防
        // 一次型（消费即清），互不覆盖。
        if let arm = BridgeSafeModeArmStore.take() {
            let applied = bootMode == .normal
            if applied {
                bootMode = .safe(
                    streak: prevLaunchStreak,
                    step: prevLaunchStep,
                    source: "bridge")
            }
            let auditOk = BridgeSafeModeArmStore
                .recordAudit(arm, applied: applied)
            DiagLog.shared.log(.info,
                "RESCUE arm consumed id="
                + "\(arm.commandId) applied="
                + (applied ? "1" : "0"))
            DiagLog.shared.log(.info,
                "RESCUE arm cleared id="
                + "\(arm.commandId) audit="
                + (auditOk ? "1" : "0"))
        }
        if case .safe(let n, let step, let source)
            = bootMode {
            DiagLog.shared.log(.error,
                "RESCUE enter streak=\(n) "
                + "step=\(step.isEmpty ? "-" : step) "
                + "src=\(source)")
        }
    }

    func load() {
        // 只读态守卫（S4）：只读句柄在位时常规加载
        // 不得顶替（ListView 以空列表 onAppear 触发
        // 本函数，只读空库会误入）——退出只读只经
        // prepareNormalStart 复位后由此重走。
        guard openMode == .none else { return }
        // 面包屑分步：先让首帧把当前步显示出来，再走 FFI；
        // 若某步硬崩，列表头会停在该步文案上（或下次启动
        // 能看到），不至于黑箱。开库延迟一拍同理。上次
        // 启动判定已前移 init（S2），此处不再重复判定。
        armWatchdog()
        launchMark(LaunchStep.open)
        timing = "启动中 · 开库…"
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + 0.05) {
            do {
                self.launchMark(LaunchStep.openFFI)
                let lib = try MomentLibrary.open(
                    path: self.storeDir + "/moment.db")
                self.lib = lib
                self.openMode = .readWrite
                DispatchQueue.main.async {
                    self.timing = "启动中 · 已开库，读数据…"
                }
                if try lib.memoCount() == 0 {
                    // 种子写入是写面（S4 拒写清单）：
                    // 只读态本函数已被入口守卫拦下，
                    // 此处再经 writeBlocked 双保险。
                    if !self.writeBlocked("seed") {
                        self.launchMark(LaunchStep.seed)
                        for m in Self.seedMemos {
                            try lib.upsertMemoJson(json: m)
                        }
                    }
                }
                try self.reload(lib: lib)
                let ready = Clock.ms()
                DispatchQueue.main.async {
                    // 「首帧」步痕口径注记（救援完整
                    // 性批，§5.1 b）：此步痕是加载链收
                    // 尾面包屑（数据就绪后写），与
                    // ListView 量测的 firstFrameMs（真
                    // 实首帧渲染时刻）是两个口径——
                    // Diag 并读时勿混（步痕看进度、
                    // firstFrameMs 看耗时）。
                    self.launchMark(LaunchStep.firstFrame)
                    self.didLoad = true
                    self.cancelWatchdog()
                    self.launchDone()
                    // S5 快照补写：判定点快照回填篇
                    // 数/附件数 + BOOT snap 证据行。
                    RescueLogStore.updateLatest { s in
                        s.memoCount = self.memos.count
                        s.attachCount = self.attachmentCount()
                    }
                    let snapDb = ((try? FileManager.default
                        .attributesOfItem(
                            atPath: self.storeDir
                                + "/moment.db"))?[.size]
                        as? NSNumber)?.int64Value ?? -1
                    DiagLog.shared.logOnce(
                        "boot-snap", .info,
                        "BOOT snap db=\(snapDb) memos="
                        + "\(self.memos.count) diag="
                        + "\(DiagLog.shared.today.count)")
                    // S9/S13 收尾：Diag 结构写盘提前
                    // flush；热更新指令后台刷新一次备
                    // 下次启动缓存（fire-and-forget）。
                    DiagLog.shared.flushStructuralPersist()
                    OpsDirectives.refreshInBackground()
                    if self.launchOnceNoticePending,
                       self.notice.isEmpty {
                        self.notice = Lang.t(
                            "notice.launch_once")
                    }
                    self.launchOnceNoticePending = false
                    self.timing = "冷启 首帧 "
                        + "\(self.firstFrameMs ?? -1)ms · 数据 "
                        + "\(ready)ms · \(self.memos.count) 篇"
                    // 真机冒烟证据行：冷启全程走完才记，
                    // 带版本号——导出日志一看便知该版在
                    // 真机冷启成功、数据篇数与耗时。
                    let ver = Bundle.main.infoDictionary?[
                        "CFBundleShortVersionString"]
                        as? String ?? "?"
                    DiagLog.shared.log(.info,
                        "SMOKE 冷启完成 v=\(ver) memos="
                        + "\(self.memos.count)"
                        + " 首帧\(self.firstFrameMs ?? -1)ms"
                        + " 数据\(ready)ms")
                }
            } catch {
                self.launchFailed()
                DispatchQueue.main.async {
                    self.didLoad = true
                    self.cancelWatchdog()
                    self.timing = "打开库失败: \(error)"
                    self.loadFailed = true
                    DiagLog.shared.log(.error,
                        "打开库失败: \(error)")
                    // SMOKE 失败行（救援完整性批，
                    // §5.1 a）：与成功行同前缀同格式，
                    // 发版清单按 SMOKE 检索不漏计失败
                    // 冷启（此前失败路只有 error 行）。
                    let ver = Bundle.main.infoDictionary?[
                        "CFBundleShortVersionString"]
                        as? String ?? "?"
                    DiagLog.shared.log(.error,
                        "SMOKE 冷启失败 v=\(ver) "
                        + "err=\(error)")
                    ErrBadge.shared.addError(
                        Lang.t("errbadge.open_db"),
                        detail: "\(error)")
                }
            }
        }
    }

    private func reload(lib: MomentLibrary) throws {
        loadStepMark(LaunchStep.readList)
        let json = try lib.listMemosJson()
        loadStepMark(LaunchStep.readParse)
        let (items, quarantined) = Self.parse(json)
        if quarantined > 0 {
            DiagLog.shared.log(.warn,
                "加载隔离：\(quarantined) 篇数据损坏已隔离"
                + "（原文保存在库内隔离区，导出备份随包附出）")
            DispatchQueue.main.async {
                self.notice = Lang.tf(
                    "notice.quarantine",
                    ["n": "\(quarantined)"])
            }
        }
        // 待删再水化（Web U3，二轮微差 16）：标记随
        // 备忘落盘，窗口内杀进程重开标记仍在——已
        // 过期（≥8 秒）在此真删，未过期者不进列表、
        // 登记待删集并按剩余时长重新 arm。
        loadStepMark(LaunchStep.rehydrate)
        let now = Self.epochMs()
        var visible: [MemoItem] = []
        var rehydrated: [(MemoItem, Int64)] = []
        for it in items {
            guard let at = it.deletedAtMs else {
                visible.append(it)
                continue
            }
            if now - at >= Self.undoWindowMs {
                if isReadOnly {
                    // S4：只读态跳过真删——仅隐藏
                    // 并记行，删除标记原样留在库里，
                    // 下次正常打开时按既有口径真删。
                    DiagLog.shared.logOnce(
                        "readonly-block-delete", .warn,
                        "READONLY write-blocked kind=delete")
                    DiagLog.shared.log(.info,
                        "只读态待删过期仅隐藏 "
                        + "id=\(it.id)")
                } else {
                    do {
                        try lib.removeMemo(id: it.id)
                        DiagLog.shared.log(.info,
                            "待删过期真删（启动清理）"
                            + "id=\(it.id)")
                    } catch {
                        DiagLog.shared.log(.error,
                            "待删过期真删失败 "
                            + "id=\(it.id): \(error)")
                    }
                }
            } else {
                rehydrated.append((it, at))
            }
        }
        // 镜像发布（快照线缺陷一根治）：主线程调用
        // 方（桥恢复/导入提交/重试/只读进入）在此同
        // 步落定，后台调用方（开库链）仍异步——旧形
        // 态恒异步派发时，恢复返回后同回合的同步消
        // 费方（场景步断言、收尾清理）读到的仍是换
        // 库前镜像，且迟到的发布块会反手覆盖清理结
        // 果把已删夹具在列表里复活。不变量：主线程
        // 上 reload 返回 ⇒ memos/pendingDeletions
        // 已与库一致。
        let publishMirror = {
            self.memos = visible
            self.touchMemos()
            self.loadFailed = false
            self.loadStepMark(LaunchStep.attachNames)
            self.refreshAttachmentNames()
            // S9 延后：附件类型表非首帧必需（列表先
            // 出、类型回填后刷行），移出首帧前同步段。
            self.deferRefreshAttachmentTypes()
            // 待删集以本次落盘标记为唯一真相重建：
            // 先撤旧计时（导入换库后旧 id 不得误删
            // 新库同名篇），再登记再水化项。
            for w in self.deletionWorks.values {
                w.cancel()
            }
            self.deletionWorks.removeAll()
            self.pendingDeletions.removeAll()
            for (it, at) in rehydrated {
                self.pendingDeletions[it.id] = (it, at)
                let left = Self.undoWindowMs - (now - at)
                self.armDeletion(id: it.id, afterMs: left)
                DiagLog.shared.log(.info,
                    "待删再水化 id=\(it.id) "
                    + "剩余\(left)ms")
            }
        }
        if Thread.isMainThread {
            publishMirror()
        } else {
            DispatchQueue.main.async(execute: publishMirror)
        }
    }

    func retryLoad() {
        // 按结局置位：失败如实回到失败态并记行，不再
        // 先清标志再 try? 吞错跌落假空态。
        if lib == nil { load(); return }
        guard let lib else { return }
        do {
            try reload(lib: lib)
        } catch {
            loadFailed = true
            DiagLog.shared.log(.error,
                "重试加载失败: \(error)")
        }
    }

    /// 待删标记落盘：以 raw 为底只改 deletedAt 键
    /// （置值 = 打标、传 nil = 摘标），不碰
    /// updatedAt（Web soft_delete/undo 同——删与
    /// 撤销不影响排序和时间显示）。失败记 error。
    private func persistDeletionMark(_ item: MemoItem,
                                     atMs: Int64?) {
        if writeBlocked("delete") { return }
        var memo = item.raw
        memo["id"] = item.id
        if let atMs {
            memo["deletedAt"] = NSNumber(value: atMs)
        } else {
            memo.removeValue(forKey: "deletedAt")
        }
        guard let lib,
              let data = try? JSONSerialization.data(
                withJSONObject: memo),
              let s = String(data: data, encoding: .utf8)
        else {
            DiagLog.shared.log(.error,
                "待删标记落盘失败 id=\(item.id)")
            return
        }
        do {
            try lib.upsertMemoJson(json: s)
        } catch {
            DiagLog.shared.log(.error,
                "待删标记落盘失败 id=\(item.id): \(error)")
        }
    }

    private func armDeletion(id: String, afterMs: Int64) {
        deletionWorks[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.commitPendingDeletion(id: id)
        }
        deletionWorks[id] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(
                Int(max(afterMs, 0))),
            execute: work)
    }

    /// 软删（二轮微差 16，Web soft_delete_memo）：
    /// 打标落盘 + 列表摘除 + 登记待删集 + 本篇独立
    /// arm 8 秒到期——连删多篇互不影响，各自到期。
    func softRemove(_ item: MemoItem) {
        if writeBlocked("delete") { return }
        // 删除点按意图行（G4），与 commit 结果行成对。
        DiagLog.shared.log(.info,
            "APP row delete tap \(item.id)")
        var it = item
        let now = Self.epochMs()
        it.raw["deletedAt"] = NSNumber(value: now)
        persistDeletionMark(it, atMs: now)
        memos.removeAll { $0.id == item.id }
        touchMemos()
        pendingDeletions[item.id] = (it, now)
        armDeletion(id: item.id,
                    afterMs: Self.undoWindowMs)
    }

    /// 撤销最近一篇待删：摘标落盘 + 回列表（到期
    /// 任务以待删集在册与否校验，摘除后自动作废）。
    func undoDeletion() {
        if writeBlocked("delete") { return }
        guard let target = pendingDeletion else { return }
        deletionWorks[target.id]?.cancel()
        deletionWorks[target.id] = nil
        pendingDeletions[target.id] = nil
        var it = target
        it.raw.removeValue(forKey: "deletedAt")
        persistDeletionMark(it, atMs: nil)
        memos.append(it)
        memos.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        touchMemos()
    }

    /// 单篇到期真删（批 C 结果口径沿用：删成功才
    /// 记已删除，失败/lib 未开记 error）。
    func commitPendingDeletion(id: String) {
        deletionWorks[id]?.cancel()
        deletionWorks[id] = nil
        guard pendingDeletions[id] != nil else { return }
        pendingDeletions[id] = nil
        if writeBlocked("delete") { return }
        if let lib {
            do {
                try lib.removeMemo(id: id)
                DiagLog.shared.log(.info,
                    "备忘已删除（撤销窗口结束）"
                    + "id=\(id)")
            } catch {
                DiagLog.shared.log(.error,
                    "删除失败 id=\(id): \(error)")
            }
        } else {
            DiagLog.shared.log(.error,
                "删除失败（库未打开）id=\(id)")
        }
    }

    /// 双形兼容：现行包装形 {"memos":[...],
    /// "quarantined":n} 与旧数组形（隔离数恒 0）。
    static func parse(_ json: String)
        -> (items: [MemoItem], quarantined: Int) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(
                with: data) else { return ([], 0) }
        let arr: [[String: Any]]
        var quarantined = 0
        if let wrap = obj as? [String: Any],
           let m = wrap["memos"] as? [[String: Any]] {
            arr = m
            quarantined = wrap["quarantined"] as? Int ?? 0
        } else if let a = obj as? [[String: Any]] {
            arr = a
        } else {
            return ([], 0)
        }
        var items = arr.map { m in
            MemoItem(
                id: m["id"] as? String ?? UUID().uuidString,
                title: m["title"] as? String ?? "",
                pinned: m["pinned"] as? Bool ?? false,
                createdAt: m["createdAt"] as? String ?? "",
                updatedAt: m["updatedAt"] as? String ?? "",
                blocks: (m["doc"] as? [[String: Any]] ?? [])
                    .map { BlockState(node: $0) },
                raw: m)
        }
        items.sort {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
        return (items, quarantined)
    }

    func persist(_ item: MemoItem) {
        if writeBlocked("persist") { return }
        // 最近编辑时刻（备份新鲜度判定：超 7 天且有新编辑）。
        UserDefaults.standard.set(
            Date().timeIntervalSince1970, forKey: "lastEditTs")
        var it = item
        it.updatedAt = Clock.isoNow()
        // 以原始 JSON 为底覆写：未建模字段（bgColor/layout 等）
        // 原样保留，避免原生编辑一字就抹掉 Web 侧数据。
        var memo = it.raw
        memo["id"] = it.id
        memo["title"] = it.title
        memo["pinned"] = it.pinned
        memo["createdAt"] = it.createdAt
        memo["updatedAt"] = it.updatedAt
        memo["doc"] = it.blocks.map { $0.flushedNode() }
        it.raw = memo
        // 结果回路（批 A）：三段失败各自记 error 并经
        // notice 告知——不再 guard 静默 return、try? 吞
        // 错后照常更新内存列表装作已保存。写入成功后
        // 才同步内存列表（列表 = 库的镜像）。
        guard let data = try? JSONSerialization.data(
                withJSONObject: memo),
              let s = String(data: data, encoding: .utf8)
        else {
            DiagLog.shared.log(.error,
                "保存失败（序列化）id=\(it.id)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.save_serialize"))
            notice = Lang.t("notice.save_serialize")
            return
        }
        guard let lib else {
            DiagLog.shared.log(.error,
                "保存失败（库未打开）id=\(it.id)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.save_db_closed"))
            notice = Lang.t("notice.save_db_closed")
            return
        }
        do {
            try lib.upsertMemoJson(json: s)
        } catch {
            DiagLog.shared.log(.error,
                "保存失败（写入）id=\(it.id): \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.save_write"),
                detail: "\(error)")
            notice = Lang.t("notice.save_write")
            return
        }
        if !notice.isEmpty { notice = "" }
        if let idx = memos.firstIndex(where: { $0.id == it.id }) {
            memos[idx] = it
            memos.sort {
                if $0.pinned != $1.pinned { return $0.pinned }
                return $0.updatedAt > $1.updatedAt
            }
            touchMemos()
        }
    }

    /// 派生数据版本（0.9.48，治 S1 趟基数）：memos 与
    /// 附件清单是列表归组（ListView.groups）的全部输
    /// 入面，两者的每个写点同步 bump 对应版本，归组
    /// 按版本读缓存——版本即失效真值源，漏 bump 即
    /// 归组过期，故写点全集由 verify [15] 计数锁定。
    /// 写点：memos = reload/create/persist/remove/
    /// softRemove/undoDeletion 六处；manifest = 名表
    /// 刷新/类型表刷新/putAttachment 登记三处。
    private(set) var memosVersion = 0
    private(set) var manifestVersion = 0
    func touchMemos() {
        memosVersion += 1
        // 搜索命中集失效触发单点（P3）：版本 bump
        // 后顺带核新鲜度——六写点与桥写同经本漏
        // 斗，消费方零补刷。
        refreshSearchHitsIfStale()
    }
    func touchManifest() { manifestVersion += 1 }

    /// 搜索命中集陈旧重算（P3）：仅由 touchMemos
    /// 在版本 bump 后调用（全仓唯一调用点）。守
    /// 卫三条件：命中集在位（未搜索/空查询恒空
    /// 转）、查询串非空、命中集版本与现行
    /// memosVersion 不等。重算失败（库未开/FFI
    /// 错）保持原集且不对齐版本——下个写点自动
    /// 重试，不把暂态失败钉成陈旧集。命中集实
    /// 际变化才记一行（结果侧量测，静默刷新不
    /// 记行）。
    func refreshSearchHitsIfStale() {
        guard searchHits != nil,
              let query = searchQuery, !query.isEmpty,
              searchHitsVersion != memosVersion
        else { return }
        guard let newHits = try? computeSearchHits(query: query)
        else { return }
        let oldHits = searchHits
        searchHits = newHits
        searchHitsVersion = memosVersion
        if newHits != oldHits {
            DiagLog.shared.log(.info,
                "APP search refresh "
                + "hits=\(newHits.count) src=libchange")
        }
    }

    /// CREATE 分段量测汇（0.9.48）：create() 置
    /// createTraceActive 并清零累计，列表归组趟与头
    /// 像 FFI 读在在位时累计并逐趟记行；EditorModel
    /// 在 settle 汇总时读取并清 active。纯量测。
    var createTraceActive = false
    var createTraceListPasses = 0
    var createTraceListMs = 0
    var createTraceAvatarMs = -1

    /// 最近一次新建的计时痕（CREATE timing）：create
    /// 入口/出口时刻，同篇 EditorModel 在 init 时按
    /// id 认领（认领即清），量测新建→首帧分段耗时。
    /// 纯量测，不参与任何业务判定。
    private(set) var createTrace:
        (id: String, start: CFAbsoluteTime,
         end: CFAbsoluteTime)?

    /// 按 id 认领并清除新建计时痕（非本篇返回 nil）。
    func consumeCreateTrace(for id: String)
        -> (start: CFAbsoluteTime,
            end: CFAbsoluteTime)? {
        guard let tr = createTrace, tr.id == id else {
            return nil
        }
        createTrace = nil
        return (tr.start, tr.end)
    }

    @discardableResult
    func create() -> MemoItem {
        let traceStart = CFAbsoluteTimeGetCurrent()
        // CREATE 分段量测开账（0.9.48）：本回合的归
        // 组趟/头像读开始累计，settle 时收口。
        createTraceActive = true
        createTraceListPasses = 0
        createTraceListMs = 0
        createTraceAvatarMs = -1
        let now = Clock.isoNow()
        let item = MemoItem(
            id: "m-" + UUID().uuidString.prefix(12).lowercased(),
            title: "", pinned: false, createdAt: now,
            updatedAt: now,
            blocks: [BlockState(node: [
                "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
                "type": "paragraph", "children": [["text": ""]],
            ])])
        persist(item)
        // 只读态（S4）：persist 已被门面拦截，不得
        // 再把未落库的新篇插进内存列表造假象。
        if memos.firstIndex(where: { $0.id == item.id }) == nil
            && !isReadOnly {
            memos.insert(item, at: 0)
            touchMemos()
        }
        DiagLog.shared.log(.info, "APP row new \(item.id)")
        createTrace = (id: item.id, start: traceStart,
                       end: CFAbsoluteTimeGetCurrent())
        return item
    }

    func remove(_ item: MemoItem) {
        if writeBlocked("delete") { return }
        // 结果侧（批 C）：库删成功才同步内存列表，
        // 失败记 error 并保留列表项（不造已删假象）；
        // lib 为 nil 显式判失败（可选链假成功同型）。
        guard let lib else {
            DiagLog.shared.log(.error,
                "删除失败（库未打开）id=\(item.id)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.delete_failed"))
            return
        }
        do {
            try lib.removeMemo(id: item.id)
            memos.removeAll { $0.id == item.id }
            touchMemos()
            DiagLog.shared.log(.info,
                "备忘已删除 id=\(item.id)")
        } catch {
            DiagLog.shared.log(.error,
                "删除失败 id=\(item.id): \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.delete_failed"),
                detail: "\(error)")
        }
    }

    func togglePin(_ item: MemoItem) {
        var it = item
        it.pinned.toggle()
        // 置顶同步刷新 updatedAt（H5，Web togglePin
        // 同口径）：刷新点在 persist 内——其无条件
        // it.updatedAt = Clock.isoNow() 并按 pinned/
        // updatedAt 重排内存列表，故本函数只翻标记
        // 即已达成（ago 变「现在」、置顶组内按更新
        // 序置前）。审计二轮曾因只读本函数误判未刷，
        // 特此明示；verify [10] 对此机制设断言。
        persist(it)
        DiagLog.shared.log(.info,
            "APP row pin tap \(item.id) pinned=\(it.pinned)")
    }

    func attachmentData(_ id: String) -> Data {
        (try? lib?.attachmentData(id: id)) ?? Data()
    }

    /// 附件清单文件名表缓存（fid → 真实文件名）：清
    /// 单是文件名的唯一真值源（Web 口径），load 时经
    /// FFI 拉全表、put 成功后同步增补。
    @Published var attachmentNames: [String: String] = [:]

    func refreshAttachmentNames() {
        guard let json = try? lib?.attachmentNamesJson(),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(
                with: data) as? [String: String] else { return }
        attachmentNames = dict
        touchManifest()
    }

    /// 附件清单 MIME 表缓存（fid → type，仅非空条
    /// 目）：判图清单优先的真值源（Web att_type_in_
    /// manifest 口径）——type 在位时以其为准（image/
    /// 开头即图、非图否决），缺失才回落扩展名判定。
    /// 原生 put 登记 type 恒空，本表通常只含导入项；
    /// load/导入后随文件名表一并刷新。
    @Published var attachmentTypes: [String: String] = [:]

    /// S9 延后入口：didLoad 后 0.3s 再刷类型表（首
    /// 帧先出列表）。reload 收尾统一经此，不再在首
    /// 帧前同步段直调 refreshAttachmentTypes。
    private func deferRefreshAttachmentTypes() {
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.3) { [weak self] in
            self?.refreshAttachmentTypes()
        }
    }

    func refreshAttachmentTypes() {
        // S13 guard 点：指令点名「附件类型」即跳过
        // 本步（判图回落扩展名口径，列表照常出）。
        if OpsDirectives.cached().isDisabled(
            LaunchStep.attachTypes) {
            DiagLog.shared.logOnce(
                "ops-skip-attachtypes", .info,
                "OPS skip step=\(LaunchStep.attachTypes)")
            return
        }
        // 步痕只在加载期记（loadStepMark 守卫）：
        // didLoad 后本步是会话内刷新，再记会把哨兵
        // 步从「会话中」倒退回加载步、前台死亡被误
        // 判启动死亡。
        loadStepMark(LaunchStep.attachTypes)
        guard let json = try? lib?.attachmentTypesJson(),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(
                with: data) as? [String: String] else { return }
        attachmentTypes = dict
        touchManifest()
    }

    /// 附件写入结果回路（批 A）：失败记 error 并回
    /// false 供调用点留痕——不再 try? 静默吞掉（块引
    /// 用着不存在的 fileId、附件永久缺失的源头）。
    /// name = 真实文件名（选图器/文件导入给出），非
    /// 空时随写入登记进清单（图片页标题查名来源）；
    /// 无名来源（粘贴图）传空串不登记。
    @discardableResult
    func putAttachment(_ id: String, _ data: Data,
                       name: String = "") -> Bool {
        if writeBlocked("attach") { return false }
        guard let lib else {
            DiagLog.shared.log(.error,
                "附件写入失败（库未打开）id=\(id)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.attach_db_closed"))
            return false
        }
        do {
            try lib.putAttachment(id: id, data: data, name: name)
            if !name.isEmpty {
                attachmentNames[id] = name
                touchManifest()
            }
            return true
        } catch {
            DiagLog.shared.log(.error,
                "附件写入失败 id=\(id): \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.attach_failed"),
                detail: "\(error)")
            return false
        }
    }

    func attachmentCount() -> Int {
        guard let json = try? lib?.attachmentIdsJson(),
              let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(
                with: data) as? [String] else { return 0 }
        return arr.count
    }

    func libraryHash() -> String {
        if let h = try? lib?.libraryHash() { return String(h) }
        return "-"
    }

    /// 只读校验（G14）：经 FFI 重读全库并重解析计数，
    /// 与内存列表篇数对照；纯读不写库。库未打开或读
    /// 失败返回 nil。
    func verifyStore() -> (count: Int, hash: String)? {
        guard let lib,
              let json = try? lib.listMemosJson()
        else { return nil }
        let (items, _) = Self.parse(json)
        return (items.count, libraryHash())
    }

    @Published var notice = ""

    /// 最近一次导出失败的原因（供备份页 toast 拼
    /// 「导出失败：{e}」，Web status.export_error
    /// 口径）；成功时清空。
    var lastExportError: String?

    /// 导出文件名（Web 口径）：此刻备份_<UTC 日期>.zip。
    func exportZip() -> URL? {
        // 实况挂点（权限批 §5.3）：整库导出起实况，
        // 函数出口统一收口（下方 defer 覆盖全部
        // return 路径，含库未打开的失败路）。
        let liveId = MomentLiveOps.shared.start(
            kind: .export, title: Lang.t("liveops.export"),
            step: Lang.t("liveops.running"), total: nil)
        defer {
            MomentLiveOps.shared.end(
                id: liveId,
                result: lastExportError == nil ? .ok : .failed,
                step: lastExportError == nil
                    ? Lang.t("liveops.done")
                    : Lang.t("liveops.failed"))
        }
        let dir = storeDir + "/exports"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        let path = dir + "/此刻备份_\(f.string(from: Date())).zip"
        // lib == nil 守卫（批 A）：旧路 try lib?. 可选
        // 链不抛错、直落成功分支记 ok 并返回不存在的
        // 文件 URL——开库失败时救援导出恰不可用。
        guard let lib else {
            lastExportError = Lang.t("status.db_not_open")
            recordOp(kind: "export", ok: false, detail: "")
            DiagLog.shared.log(.error, "导出失败: 库未打开")
            ErrBadge.shared.addError(
                Lang.t("errbadge.export_failed"))
            return nil
        }
        do {
            try lib.exportBackup(zipPath: path)
            lastExportError = nil
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "lastExportTs")
            let url = URL(fileURLWithPath: path)
            recordOp(kind: "export", ok: true,
                     detail: url.lastPathComponent)
            DiagLog.shared.log(.info,
                "导出备份 \(url.lastPathComponent)")
            return url
        } catch {
            lastExportError = "\(error)"
            recordOp(kind: "export", ok: false, detail: "")
            DiagLog.shared.log(.error, "导出失败: \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.export_failed"),
                detail: "\(error)")
            return nil
        }
    }

    /// 备份操作记录（Web 口径）：存 20 条、成功失败都记；
    /// 条目 = 状态 + 类型 + 时刻 + 详情（成功为文件名）。
    struct BackupOp: Codable {
        var ts: Double
        var ok: Bool
        var kind: String  // export | import
        var detail: String
    }

    func recordOp(kind: String, ok: Bool, detail: String) {
        var ops = Self.loadOps()
        ops.insert(BackupOp(ts: Date().timeIntervalSince1970,
                            ok: ok, kind: kind, detail: detail),
                   at: 0)
        if let data = try? JSONEncoder().encode(
            Array(ops.prefix(20))) {
            UserDefaults.standard.set(data, forKey: "backupOpsV2")
        }
    }

    static func loadOps() -> [BackupOp] {
        guard let data = UserDefaults.standard.data(
                forKey: "backupOpsV2"),
              let ops = try? JSONDecoder().decode(
                [BackupOp].self, from: data) else { return [] }
        return ops
    }

    /// FFI 统计行 `memos=N attachments=M` 解析。
    static func parseStats(_ s: String) -> (Int, Int)? {
        var m: Int?
        var a: Int?
        for part in s.split(separator: " ") {
            let kv = part.split(separator: "=")
            guard kv.count == 2, let v = Int(kv[1]) else {
                continue
            }
            if kv[0] == "memos" { m = v }
            if kv[0] == "attachments" { a = v }
        }
        guard let m, let a else { return nil }
        return (m, a)
    }

    private var pendingImportPath: String {
        storeDir + "/import-pending.zip"
    }

    /// 导入第一步（Web 口径）：先把所选文件暂存并整包
    /// 校验，校验通过才进入确认；失败直接报错、数据未动。
    /// 返回值只表达校验成败（BK-1 契约拆分）：校验统计
    /// 是附带产物，解析不出不许反转成败——旧契约以
    /// parseStats 的 nil 判失败，合法文件只因计数解析
    /// 失败被误报无效。stage 侧计数无人读、不设承载
    /// 字段（BK-2 清理）；计数对账在 commit 回读面。
    func stageImport(from picked: URL) -> Bool {
        let scoped = picked
            .startAccessingSecurityScopedResource()
        defer {
            if scoped {
                picked.stopAccessingSecurityScopedResource()
            }
        }
        try? FileManager.default.removeItem(
            atPath: pendingImportPath)
        do {
            // lib == nil 显式守卫（AUD-C-01，与
            // exportZip 同口径）：旧路可选链
            // 短路回空串、直落 return true——库未打
            // 开时任何包都「校验通过」，假成功。抛
            // 既有「库未打开」文案走下方 catch 的失
            // 败收口（Diag + ErrBadge + false）。
            guard let lib else {
                throw NSError(
                    domain: "Moment.Backup", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            Lang.t("status.db_not_open")])
            }
            try FileManager.default.copyItem(
                at: picked,
                to: URL(fileURLWithPath: pendingImportPath))
            _ = try lib.validateBackup(
                zipPath: pendingImportPath)
            return true
        } catch {
            DiagLog.shared.log(.error,
                "导入校验失败: \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.import_failed"),
                detail: "\(error)")
            return false
        }
    }

    /// 导入提交结果（BK-1 契约拆分）：成败只由
    /// importBackup 本体决定；统计计数是附带产物，
    /// 解析不出时降级为「计数未知」（stats = nil），
    /// 不许反转成败。旧契约把两者耦合在 (Int, Int)?
    /// 里：计数解析失败（边沿 A）或提交后重载失败
    /// （边沿 B）都整体回 nil，消费方误报「导入失败
    /// （现有数据未动）」——数据其实已换。
    enum ImportOutcome {
        case success(stats: (Int, Int)?)
        case failure
    }

    /// 导入第二步：确认后整库替换（校验已过）。
    func commitStagedImport() -> ImportOutcome {
        if writeBlocked("import") { return .failure }
        // 实况挂点（权限批 §5.3）：整库替换（恢复
        // 类）起实况，成功/失败出口收口。
        let liveId = MomentLiveOps.shared.start(
            kind: .restore, title: Lang.t("liveops.import"),
            step: Lang.t("liveops.running"), total: nil)
        var importOk = false
        defer {
            MomentLiveOps.shared.end(
                id: liveId,
                result: importOk ? .ok : .failed,
                step: importOk
                    ? Lang.t("liveops.done")
                    : Lang.t("liveops.failed"))
        }
        // lib == nil 显式守卫（AUD-C-01，与
        // exportZip 同口径）：旧路可选链回
        // 空串直落成功收口——库未打开时整库根本
        // 没换却弹恢复成功，假成功。如实失败（与
        // 下方 catch 同形态三件：记账 + Diag +
        // ErrBadge）；位置在 liveId 建立后，defer
        // 以 importOk=false 收 .failed。
        guard let lib else {
            recordOp(kind: "import", ok: false, detail: "")
            DiagLog.shared.log(.error, "导入失败: 库未打开")
            ErrBadge.shared.addError(
                Lang.t("errbadge.import_failed"))
            return .failure
        }
        let result: String
        do {
            result = try lib.importBackup(
                zipPath: pendingImportPath)
        } catch {
            recordOp(kind: "import", ok: false, detail: "")
            DiagLog.shared.log(.error, "导入失败: \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.import_failed"),
                detail: "\(error)")
            return .failure
        }
        // 提交点：importBackup 成功即整库已换，成败、
        // 操作记录与实况收口都以此为准。其后的计数
        // 解析与呈现重载不在成败域内（BK-1 根治）。
        importOk = true
        recordOp(kind: "import", ok: true,
                 detail: pickedImportName ?? "")
        DiagLog.shared.log(.info, "导入备份 \(result)")
        let stats = Self.parseStats(result)
        if stats == nil {
            DiagLog.shared.log(.warn,
                "IMPORT stats unparsed: \(result)")
        }
        // 呈现重载是提交后的独立故障面：失败只记
        // Diag + notice（数据已换、列表可能不是最新），
        // 不回滚成败、不再记 ok:false 覆盖真值。
        // lib 已由上方 AUD-C-01 守卫确立非空，
        // 直接重载（旧 if let 包装随守卫收敛）。
        do {
            try reload(lib: lib)
        } catch {
            DiagLog.shared.log(.error,
                "导入后重载失败: \(error)")
            DispatchQueue.main.async {
                self.notice = Lang.t(
                    "notice.import_reload_failed")
            }
        }
        return .success(stats: stats)
    }

    /// 桥快照恢复的结局（M3 backup_restore_
    /// snapshot）：restored 载恢复后对账值（在册
    /// 未删篇数 + libraryHash，FFI 直读口径，与
    /// 快照清单 appendManifest 的记账口径同
    /// 源）；failed 的 reason 只回阶段名（closed/
    /// readonly/validate/import/verify），细节
    /// 在 Diag 行。
    enum BridgeRestoreOutcome {
        case restored(count: Int, hash: String)
        case failed(reason: String)
    }

    /// 桥快照恢复提交点（M3，与用户导入同一条
    /// 链的内部同路：validateBackup 整包校验 →
    /// importBackup validate-then-swap 换库 →
    /// reload 呈现重载 → FFI 直读对账）。与
    /// commitStagedImport 的分工：后者吃暂存路
    /// 径 + 备份页记账/实况/统计回执；本路吃桥快
    /// 照 zip 路径，回执只走对账值，记账以
    /// recordOp(kind: import) 同账留痕。成败口
    /// 径沿 BK-1：换库成功即已恢复，其后 reload
    /// 失败只是呈现面故障、单独记行不反转成败
    /// （对账走 FFI 直读、不依赖 reload 后的内
    /// 存镜像）。
    func bridgeRestoreFromSnapshot(
        zipPath: String) -> BridgeRestoreOutcome {
        if writeBlocked("import") {
            return .failed(reason: "readonly")
        }
        guard let lib else {
            DiagLog.shared.log(.error,
                "BRIDGE restore failed: 库未打开")
            return .failed(reason: "closed")
        }
        do {
            _ = try lib.validateBackup(
                zipPath: zipPath)
        } catch {
            DiagLog.shared.log(.error,
                "BRIDGE restore validate failed: "
                + "\(error)")
            return .failed(reason: "validate")
        }
        let result: String
        do {
            result = try lib.importBackup(
                zipPath: zipPath)
        } catch {
            recordOp(kind: "import", ok: false,
                     detail: "bridge-snapshot")
            DiagLog.shared.log(.error,
                "BRIDGE restore import failed: "
                + "\(error)")
            return .failed(reason: "import")
        }
        recordOp(kind: "import", ok: true,
                 detail: "bridge-snapshot")
        DiagLog.shared.log(.info,
            "BRIDGE restore import \(result)")
        do {
            try reload(lib: lib)
        } catch {
            DiagLog.shared.log(.error,
                "BRIDGE restore reload failed: "
                + "\(error)")
        }
        guard let json = try? lib.listMemosJson()
        else {
            return .failed(reason: "verify")
        }
        let (items, _) = Self.parse(json)
        let active = items.filter {
            $0.deletedAtMs == nil
        }.count
        return .restored(count: active,
                         hash: libraryHash())
    }

    var pickedImportName: String?

    /// 附件计数（Web 口径）：全部备忘 doc 顶层 attachment
    /// 块引用的 fileId 去重（不含库内孤儿附件）。
    func referencedAttachmentCount() -> Int {
        var ids = Set<String>()
        for m in memos {
            for b in m.blocks where b.type == "attachment" {
                let attrs = b.node["attrs"] as? [String: Any]
                    ?? [:]
                if let f = attrs["fileId"] as? String {
                    ids.insert(f)
                }
                let items = attrs["items"]
                    as? [[String: Any]] ?? []
                for it in items {
                    if let f = it["fileId"] as? String {
                        ids.insert(f)
                    }
                }
            }
        }
        return ids.count
    }

    /// 按 fileId 查真实文件名（图片页标题口径）：查
    /// 名序 = 附件清单（manifest）优先（Web att_
    /// name_in_manifest 同序）→ 扫各备忘块节点
    /// （attachment/gallery）带的名字 → 都无回
    /// nil（AUD-D-03 注释对齐：旧注「唯一真值源」
    /// 与实序不符——清单只是第一顺位）。
    func attachmentName(for fid: String?) -> String? {
        guard let fid else { return nil }
        if let n = attachmentNames[fid], !n.isEmpty {
            return n
        }
        for m in memos {
            for b in m.blocks {
                let attrs = b.node["attrs"] as? [String: Any]
                    ?? [:]
                if b.type == "attachment" {
                    if attrs["fileId"] as? String == fid,
                       let n = attrs["name"] as? String {
                        return n
                    }
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items
                        where it["fileId"] as? String == fid {
                        if let n = it["name"] as? String {
                            return n
                        }
                    }
                }
                if b.type == "gallery" {
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items
                        where it["fileId"] as? String == fid {
                        if let n = it["name"] as? String {
                            return n
                        }
                    }
                }
                if b.fileId == fid,
                   let n = b.node["name"] as? String {
                    return n
                }
            }
        }
        return nil
    }

    // ── 反向链接（Web wiki 口径）：他篇正文（跳过代码
    // 块子树、剥反引号段）出现 [[标题]] 即引用本篇；键 =
    // 标题去 # 后缀、去空白、小写；标题空/「无标题」无链。
    static func wikiKey(_ title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "无标题" { return "" }
        return (t.split(separator: "#").first
            .map(String.init) ?? t)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// 反链目标提取（Web wiki.rs 管线逐趟移植，二
    /// 轮 F12 整段重写）：① collect——递归收 text
    /// 叶，code 系子树（code/codeblock/fencedcode/
    /// inlinecode）整棵跳过，叶以 "\n" 拼源；② 反
    /// 引号 run 配对整段剥；③ 转义 \[[…]] 整段剔
    /// 除；④ 扫描 [[…]]。旧实现四分叉已除：管道式
    /// 不拆 |、转义未剔、反引号单字奇偶切分（双反
    /// 引号段内仍计、落单后全文被吞）、inner 含单
    /// ]/换行仍成键另加 200 字上限——全按 Web 语义
    /// 收口（200 字上限删除）。
    static func wikiTargets(
        inDoc doc: [[String: Any]]) -> Set<String> {
        var texts: [String] = []
        func walk(_ node: [String: Any]) {
            let ty = (node["type"] as? String ?? "")
                .lowercased()
            if ["code", "codeblock", "fencedcode",
                "inlinecode"].contains(ty) { return }
            if let t = node["text"] as? String {
                texts.append(t)
            }
            if let kids = node["children"]
                as? [[String: Any]] {
                kids.forEach(walk)
            }
            if let items = (node["attrs"]
                as? [String: Any])?["items"]
                as? [[String: Any]] {
                items.forEach(walk)
            }
        }
        doc.forEach(walk)
        let joined = texts.joined(separator: "\n")
        let clean = stripEscapedWiki(
            stripBacktickSpans(joined))
        return scanWikiTargets(clean)
    }

    /// 反引号 run 配对剥离（Web strip_backtick_spans
    /// 逐字移植）：i 处量 run 长、其后找同形 run 子
    /// 串——命中则 [i, 闭合 run 末) 整段删、从闭合
    /// 处续扫；未命中 i 前进 1（下一位以更短 run 重
    /// 试）。定界符只有 ASCII '`'，字符级与 Web 字
    /// 节级等价。
    private static func stripBacktickSpans(
        _ s: String) -> String {
        let chars = Array(s)
        let n = chars.count
        var out: [Character] = []
        var seg = 0
        var i = 0
        while i < n {
            if chars[i] == "`" {
                var run = 1
                while i + run < n && chars[i + run] == "`" {
                    run += 1
                }
                var close: Int? = nil
                var k = i + run
                while k + run <= n {
                    if Array(chars[k..<(k + run)])
                        == Array(chars[i..<(i + run)]) {
                        close = k
                        break
                    }
                    k += 1
                }
                if let close {
                    out.append(contentsOf: chars[seg..<i])
                    i = close + run
                    seg = i
                    continue
                }
            }
            i += 1
        }
        out.append(contentsOf: chars[seg..<n])
        return String(out)
    }

    /// 转义 \[[…]] 剔除（Web remove_escaped_wiki
    /// 逐字移植）：\[[ 起、inner 禁单 ]/换行、]] 闭
    /// 合才整段删；不成立则逐字保留。
    private static func stripEscapedWiki(
        _ s: String) -> String {
        let chars = Array(s)
        let n = chars.count
        var out: [Character] = []
        var seg = 0
        var i = 0
        while i < n {
            if chars[i] == "\\", i + 2 < n,
               chars[i + 1] == "[", chars[i + 2] == "[" {
                var j = i + 3
                var ok = true
                while j < n {
                    if chars[j] == "]" {
                        if j + 1 < n && chars[j + 1] == "]" {
                            break
                        }
                        ok = false
                        break
                    }
                    if chars[j] == "\n" || chars[j] == "\r" {
                        ok = false
                        break
                    }
                    j += 1
                }
                if ok && j < n {
                    out.append(contentsOf: chars[seg..<i])
                    i = j + 2
                    seg = i
                    continue
                }
            }
            i += 1
        }
        out.append(contentsOf: chars[seg..<n])
        return String(out)
    }

    /// [[…]] 目标扫描（Web wiki_targets_of_clean
    /// 逐字移植）：inner 禁单 ]/换行；拆 | 取目标、
    /// 带 | 时标签须非空、目标须非空（不成立也整段
    /// 消费）；键经 wikiTargetKey 归一。
    private static func scanWikiTargets(
        _ clean: String) -> Set<String> {
        let chars = Array(clean)
        let n = chars.count
        var out = Set<String>()
        var i = 0
        while i + 1 < n {
            if chars[i] == "[" && chars[i + 1] == "[" {
                var j = i + 2
                var ok = true
                while j < n {
                    if chars[j] == "]" {
                        if j + 1 < n && chars[j + 1] == "]" {
                            break
                        }
                        ok = false
                        break
                    }
                    if chars[j] == "\n" || chars[j] == "\r" {
                        ok = false
                        break
                    }
                    j += 1
                }
                if ok && j < n {
                    let inner = String(chars[(i + 2)..<j])
                    let parts = inner.split(
                        separator: "|", maxSplits: 1,
                        omittingEmptySubsequences: false)
                    let target = parts.first
                        .map(String.init) ?? ""
                    let labelOk = parts.count < 2
                        || !parts[1].isEmpty
                    if labelOk && !target.isEmpty {
                        let key = wikiTargetKey(target)
                        if !key.isEmpty {
                            out.insert(key)
                        }
                    }
                    i = j + 2
                    continue
                }
            }
            i += 1
        }
        return out
    }

    /// 目标键归一（Web wiki_title_key）：取首个 #
    /// 之前段 → trim → 小写。# 在首位时首段为空串
    /// （Rust split 语义）——与标题侧 wikiKey 分开
    /// 实现，后者的 Swift split 会吞首位空段。
    private static func wikiTargetKey(
        _ target: String) -> String {
        let head = target.firstIndex(of: "#")
            .map { String(target[..<$0]) } ?? target
        return head.trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    /// wiki 目标 → 备忘（标题经 wikiKey 归一后全等
    /// 匹配；MD 预览内 wiki 点按跳篇用）。
    func memo(forWikiTarget target: String) -> MemoItem? {
        let key = Self.wikiKey(target)
        guard !key.isEmpty else { return nil }
        return memos.first {
            Self.wikiKey($0.title) == key
        }
    }

    func backlinks(forTitle title: String,
                   excludeId: String) -> [MemoItem] {
        let key = Self.wikiKey(title)
        guard !key.isEmpty else { return [] }
        return memos.filter { m in
            m.id != excludeId
                && Self.wikiTargets(
                    inDoc: m.raw["doc"]
                        as? [[String: Any]] ?? [])
                    .contains(key)
        }
    }

    // ── 备忘头像（avatars 通道，值 = data URL 字符串，
    // 与 Web/ZIP 互通；空串缓存表示无头像） ──
    @Published var avatarCache: [String: String] = [:]

    func avatarDataURL(for id: String) -> String? {
        guard let v = avatarCache[id], !v.isEmpty else {
            return nil
        }
        return v
    }

    /// 头像首读在途集（同 id 去重：列表多行与编辑页
    /// 页眉可同篇并发首读，只走一趟 FFI）。
    private var avatarLoadsInFlight: Set<String> = []

    /// 头像加载（0.9.48 根治 S1 触发源）：FFI 读改
    /// 后台队列、主线程只回写缓存——旧实现是主线程
    /// 同步 FFI + 写 avatarCache（@Published），新
    /// 篇头像必未缓存，列表新行/编辑页页眉的
    /// onAppear 在转场中段同步付一趟 FFI 并引爆
    /// ListView 整趟归组重算。异步化后首帧只出占位
    /// （恐龙线稿），回写发布仍会引 ListView 一趟
    /// body，但归组已按版本缓存、是廉价读缓存（见
    /// fix_new_note_transition_round2）。在途期间被
    /// setAvatar 写过的值不覆盖；读到非空头像时经
    /// 既有 .momentAvatarChanged 通道通知 AvatarView
    /// 回读（空头像不发，避免无谓刷新）。
    func loadAvatar(for id: String) {
        if avatarCache[id] != nil { return }
        if avatarLoadsInFlight.contains(id) { return }
        avatarLoadsInFlight.insert(id)
        let lib = self.lib
        DispatchQueue.global(qos: .userInitiated).async {
            let t0 = CFAbsoluteTimeGetCurrent()
            let data = (try? lib?.avatarData(memoId: id))
                ?? Data()
            let ms = Int((CFAbsoluteTimeGetCurrent()
                - t0) * 1000)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.avatarLoadsInFlight.remove(id)
                if self.createTraceActive {
                    self.createTraceAvatarMs = ms
                    DiagLog.shared.log(.info,
                        "CREATE avatar ms=\(ms)")
                }
                if self.avatarCache[id] != nil { return }
                let url = String(data: data,
                                 encoding: .utf8) ?? ""
                self.avatarCache[id] = url
                if !url.isEmpty {
                    NotificationCenter.default.post(
                        name: .momentAvatarChanged,
                        object: id)
                }
            }
        }
    }

    func setAvatar(for id: String, dataURL: String?) {
        if writeBlocked("attach") { return }
        let bytes = dataURL.map { Data($0.utf8) } ?? Data()
        // 结果侧（批 C）：写入成功才更新缓存/发通知/
        // 记成功行，失败记 error——不再 try? 后无条件
        // 记成功（意图冒充结果）。
        guard let lib else {
            DiagLog.shared.log(.error,
                "头像写入失败（库未打开）\(id)")
            return
        }
        do {
            try lib.setAvatar(memoId: id, data: bytes)
            avatarCache[id] = dataURL ?? ""
            NotificationCenter.default.post(
                name: .momentAvatarChanged, object: id)
            DiagLog.shared.log(.info, dataURL == nil
                ? "头像恢复默认 \(id)" : "头像已设置 \(id)")
        } catch {
            DiagLog.shared.log(.error,
                "头像写入失败 \(id): \(error)")
        }
    }

    /// 搜索命中计算单点（P3）：FTS 加已加载
    /// memos 的 haystack 补充扫描，结果按 memos
    /// 序。库未开回 nil；FFI 失败抛错，由调用方
    /// 决定呈现（search 层记行/徽标，桥与失效刷
    /// 新静默收口）。匹配逻辑全仓一份，search、
    /// bridgeSearchIds、失效刷新三路共用。
    func computeSearchHits(query: String) throws -> [String]? {
        guard let lib else { return nil }
        let json = try lib.searchIdsJson(query: query)
        let data = json.data(using: .utf8)
        var hits = Set((try? JSONSerialization.jsonObject(
            with: data ?? Data())) as? [String] ?? [])
        // 补充扫描（Web matches_search 口径）：FTS 只覆
        // 盖标题+正文 text，卡片 meta 白名单字段、attrs
        // 与条目的 url 不在其中——对已加载备忘的 raw 按
        // 同口径提取拼装文本做整串子串匹配，并入结果。
        // 注：附件文件名与卡片顶层 url Web 亦不匹配，
        // 不扩入（等价而非超过）。
        let needle = query.lowercased()
        for m in memos where !hits.contains(m.id) {
            if Self.searchHaystack(of: m).contains(needle) {
                hits.insert(m.id)
            }
        }
        return memos.map(\.id).filter {
            hits.contains($0)
        }
    }

    func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        // 命中集三同步（P3）：每条置 hits 的路径
        // 同步记 query 与当时 memosVersion，失效
        // 判定才有据；空查询三者同清。
        if query.isEmpty {
            searchHits = nil
            searchQuery = nil
            searchHitsVersion = -1
            return
        }
        guard let lib else {
            searchHits = []
            searchQuery = query
            searchHitsVersion = memosVersion
            DiagLog.shared.log(.error,
                "搜索失败（库未打开）")
            ErrBadge.shared.addWarn(
                Lang.t("errbadge.search_failed"))
            return
        }
        do {
            // 计算单点共用（P3）：lib 在位时不回
            // nil（nil 仅库未开，已由上方守卫排
            // 除），?? [] 仅作可选收口。
            searchHits = try computeSearchHits(query: query) ?? []
            searchQuery = query
            searchHitsVersion = memosVersion
            // 结果侧（批 C）：0 命中记一行（排障关键
            // 信号）；有命中走 logOnce 同查询只记首行
            // （G4/G7，Web log_once("search:{q}") 口
            // 径），逐键调用不刷屏。
            if searchHits?.isEmpty == true {
                DiagLog.shared.log(.info,
                    "搜索无结果 qlen=\(query.count)")
            } else {
                DiagLog.shared.logOnce(
                    "search:\(query)", .info,
                    "APP search '\(query)' "
                    + "hits=\(searchHits?.count ?? 0)")
            }
        } catch {
            // FFI 失败不再静默吞成空结果（批 C）。
            searchHits = []
            searchQuery = query
            searchHitsVersion = memosVersion
            DiagLog.shared.log(.error,
                "搜索失败: \(error)")
            ErrBadge.shared.addWarn(
                Lang.t("errbadge.search_failed"),
                detail: "\(error)")
        }
    }

    /// 桥只读搜索访问器（M1）：与 search(_:) 同口
    /// 径（FTS + raw 补充扫描、结果按 memos 序），
    /// 但不写 searchHits、不记 UI 侧日志/徽标——桥
    /// 调用不扰动界面状态。库未开或 FFI 失败回
    /// nil（与「搜过、无命中」的空数组区分）。
    func bridgeSearchIds(_ q: String) -> [String]? {
        let query = q.trimmingCharacters(
            in: .whitespaces)
        if query.isEmpty { return [] }
        // 计算单点共用（P3）：库未开回 nil、FFI
        // 失败抛错——桥口径两者同归 nil，try? 收口。
        return try? computeSearchHits(query: query)
    }

    /// Web walk_node/walk_value 口径的拼装文本：标题 +
    /// 节点 text（递归）+ attrs.text + attrs.url（非
    /// data:）+ attrs.items[].url/text + meta 白名单键。
    static func searchHaystack(of memo: MemoItem) -> String {
        var parts: [String] = [memo.title]
        func walkNode(_ n: [String: Any]) {
            if let t = n["text"] as? String { parts.append(t) }
            if let kids = n["children"] as? [[String: Any]] {
                kids.forEach(walkNode)
            }
            if let attrs = n["attrs"] as? [String: Any] {
                if let t = attrs["text"] as? String {
                    parts.append(t)
                }
                if let u = attrs["url"] as? String,
                   !u.hasPrefix("data:") {
                    parts.append(u)
                }
                if let items = attrs["items"]
                    as? [[String: Any]] {
                    for it in items {
                        if let u = it["url"] as? String,
                           !u.hasPrefix("data:") {
                            parts.append(u)
                        }
                        walkNode(it)
                    }
                }
            }
            if let meta = n["meta"] as? [String: Any] {
                for key in ["text", "title", "subtitle",
                            "source", "name", "label", "alt",
                            "description", "content", "url"] {
                    if let s = meta[key] as? String {
                        // url 键与 attrs 两处同口径滤
                        // data:（AUD-A-02 附记）：内嵌
                        // 数据 URL 非可搜文本且体积巨
                        // 大、会污染 haystack；meta 循
                        // 环原为唯一漏滤面。
                        if key == "url",
                           s.hasPrefix("data:") { continue }
                        parts.append(s)
                    }
                }
            }
        }
        (memo.raw["doc"] as? [[String: Any]] ?? [])
            .forEach(walkNode)
        return parts.joined(separator: "\n").lowercased()
    }

    static let seedMemos: [String] = [
        """
        {"id":"guide","title":"使用指南","pinned":true,
         "createdAt":"2026-11-26T00:00:00.000Z",
         "updatedAt":"2026-11-26T00:00:00.000Z",
         "doc":[
          {"id":"g1","type":"heading","attrs":{"level":2},
           "children":[{"text":"欢迎来到此刻（原生版）"}]},
          {"id":"g2","type":"paragraph",
           "children":[{"text":"这是原生阶段 2 首版：数据存在 Rust Core 的 SQLite 库里，与 Web 版同一套格式，ZIP 可互通（导入导出在后续轮）。"}]},
          {"id":"g3","type":"todo","attrs":{"checked":true},
           "children":[{"text":"列表：日期分组、搜索、下拉外手势都已接"}]},
          {"id":"g4","type":"todo","attrs":{"checked":false},
           "children":[{"text":"编辑页：点开任意一篇，试拼音组字与长按拖块排序"}]},
          {"id":"g5","type":"paragraph",
           "children":[{"text":"图片、附件等非文本块本版先只读占位，后续轮补齐。"}]}]}
        """,
        """
        {"id":"welcome","title":"第一篇备忘",
         "createdAt":"2026-11-26T00:30:00.000Z",
         "updatedAt":"2026-11-26T00:30:00.000Z",
         "doc":[
          {"id":"w1","type":"paragraph",
           "children":[{"text":"点右上角 + 新建一篇，或点开这篇直接改。所有修改自动保存。"}]}]}
        """,
    ]
}

// ── 行内标记 ⇄ NSAttributedString ─────────────────
enum Marks {
    /// 文字大小跟随系统（Dynamic Type）：Web 的 14/16/19
    /// 分级是接不到系统设置时的替代口径；原生有系统 API
    /// 则走更优路——UIFontMetrics 按文本样式缩放基准字。
    /// 实现已收口单源工厂（fix_dynamic_type_follow）：
    /// 缩放以 FontHub 类别的显式 trait 计算，不依赖调
    /// 用点当时的环境 trait；本体只作编辑器/MD 链的
    /// 具名入口，勿在此再造 metrics。
    static func dynFont(size: CGFloat,
                        weight: UIFont.Weight = .regular,
                        style: UIFont.TextStyle = .body,
                        mono: Bool = false) -> UIFont {
        FontFactory.uiFont(size: size, weight: weight,
                           style: style, mono: mono)
    }

    /// 双栏（spread）视口宽：>0 时标题字号走 Web 的
    /// vw clamp（editor.css @media spread 段）；由
    /// EditorView.syncWide 喂入，非双栏置 0。
    static var spreadWidth: CGFloat = 0

    static func baseFont(for block: BlockState) -> UIFont {
        switch block.type {
        case "heading":
            // Web --md-heading 尺度：28 / 23 / 20，字重 750；
            // 双栏时按 vw clamp 收窄（h1: clamp(23, 2.4vw,
            // 28)、h2: clamp(20, 2vw, 23)、h3: clamp(17,
            // 1.7vw, 20)）。
            let vw = Marks.spreadWidth
            let size: CGFloat
            if vw > 0 {
                size = block.level <= 1
                    ? min(28, max(23, vw * 0.024))
                    : block.level == 2
                    ? min(23, max(20, vw * 0.020))
                    : min(20, max(17, vw * 0.017))
            } else {
                size = block.level <= 1 ? 28
                    : block.level == 2 ? 23
                    : block.level == 3 ? 20 : 17
            }
            let style: UIFont.TextStyle = block.level <= 1
                ? .title1 : block.level == 2 ? .title2 : .title3
            // 字重 750：SF 无此档，以 .heavy 近似（线 1
            // #3；.bold 700 偏轻 50）。
            return dynFont(size: size, weight: .heavy,
                           style: style)
        case "quote", "callout":
            return dynFont(size: 14, style: .subheadline)
        case "codeBlock":
            return dynFont(size: 13, mono: true)
        default:
            return dynFont(size: 16)
        }
    }

    /// 阅读节奏（Web .editor-body 口径）：正文行高 1.75、
    /// 引用/提示 1.6、标题 1.28——以段落样式覆到整串。
    static func withRhythm(_ attr: NSAttributedString,
                           block: BlockState)
        -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        switch block.type {
        case "heading":
            // H1 行高 1.2、余 1.28（线 1 #5）。
            ps.lineHeightMultiple = block.level <= 1
                ? 1.2 : 1.28
        case "quote": ps.lineHeightMultiple = 1.6
        case "callout": ps.lineHeightMultiple = 1.65
        case "codeBlock": ps.lineHeightMultiple = 1.6
        default: ps.lineHeightMultiple = 1.75
        }
        let out = NSMutableAttributedString(attributedString: attr)
        let full = NSRange(location: 0, length: out.length)
        out.addAttribute(.paragraphStyle, value: ps, range: full)
        if block.type == "heading", out.length > 0 {
            // 标题字距 −0.02em（线 1 #4）。
            let f = out.attribute(.font, at: 0,
                effectiveRange: nil) as? UIFont
            out.addAttribute(.kern,
                value: -(f?.pointSize ?? 16) * 0.02,
                range: full)
        }
        applyHighlightTint(out)
        return out
    }

    /// 高亮口径（Web 定案）：==…== 是字面文本（编辑态保
    /// 留字面、渲染侧切 <mark>）；编辑面只给字面段加底色
    /// 反馈（--fill-highlight rgba(255,204,0,.25)），不改
    /// 字体——避免回读把高亮误判成加粗。不入 runs 模型。
    static func applyHighlightTint(
        _ out: NSMutableAttributedString) {
        let s = out.string
        guard s.contains("==") else { return }
        let bg = T.fillHighlightUI
        var searchStart = s.startIndex
        while let open = s.range(
            of: "==", range: searchStart..<s.endIndex) {
            let afterOpen = open.upperBound
            guard let close = s.range(
                of: "==", range: afterOpen..<s.endIndex),
                close.lowerBound > afterOpen else {
                searchStart = afterOpen
                continue
            }
            let ns = NSRange(open.lowerBound..<close.upperBound,
                             in: s)
            out.addAttribute(.backgroundColor, value: bg,
                             range: ns)
            searchStart = close.upperBound
        }
    }

    /// 行内代码底（Web --code-bg 实色，动态明暗）：
    /// 值单源在 T.codeBgUI（与 codeBg 同账），此处
    /// 只作 Marks 内的具名入口（fix_dark_mode_full
    /// 归令，此前自持 trait 闭包散写同值）。
    static var inlineCodeBg: UIColor { T.codeBgUI }

    static func font(base: UIFont, bold: Bool, italic: Bool,
                     code: Bool) -> UIFont {
        if code {
            // 行内代码 0.85em（线 1 #9）。
            return .monospacedSystemFont(
                ofSize: base.pointSize * 0.85,
                weight: bold ? .bold : .regular)
        }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let d = base.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: d, size: base.pointSize)
        }
        return base
    }

    /// 正文基准色单点（fix_dark_mode_full 定案）：
    /// 普通 run 必须显式带动态前景色。旧形态 run
    /// 无前景色、只靠承载视图的 textColor 兜底——
    /// TextKit 2 承载下 textColor 不达已设置
    /// attributedText 的渲染，深色外观时正文恒渲
    /// 默黑（浅色下默黑恰与正色同值、不可见）；
    /// 同页 applyDoneStyle 的显式动态色却随外观
    /// 翻转，构成对照实证。链接/公式失败 run 在
    /// 下方分支后赋值覆写本基准，口径不变。
    static func attributed(runs: [[String: Any]],
                           base: UIFont,
                           baseColor: UIColor = T.textMainUI)
        -> NSAttributedString {
        let out = NSMutableAttributedString()
        for r in runs {
            let t = r["text"] as? String ?? ""
            if t.isEmpty { continue }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font(base: base,
                            bold: r["bold"] as? Bool ?? false,
                            italic: r["italic"] as? Bool ?? false,
                            code: r["code"] as? Bool ?? false),
                .foregroundColor: baseColor,
            ]
            if r["code"] as? Bool ?? false {
                // 行内代码底色（Web --code-bg；padding/
                // radius 在属性串无对应面，登记近似）。
                attrs[.backgroundColor] = inlineCodeBg
            }
            if r["highlight"] as? Bool ?? false {
                // 高亮（Web .moment-highlight）：底
                // --fill-highlight + 字重 600。padding
                // 0.28em/radius 4 在 NSAttributedString
                // 无对应面（行内代码同例，登记近似）；
                // 字重以 weight trait 重建（与 bold
                // 叠加时 bold 轨优先，不再覆写）。
                attrs[.backgroundColor] = T.fillHighlightUI
                if !(r["bold"] as? Bool ?? false) {
                    let f = attrs[.font] as? UIFont ?? base
                    let fd = f.fontDescriptor
                        .addingAttributes([
                            .traits: [
                                UIFontDescriptor.TraitKey
                                    .weight:
                                    UIFont.Weight.semibold,
                            ],
                        ])
                    attrs[.font] = UIFont(
                        descriptor: fd, size: f.pointSize)
                }
            }
            if r["underline"] as? Bool ?? false {
                attrs[.underlineStyle] = NSUnderlineStyle
                    .single.rawValue
            }
            if r["strikethrough"] as? Bool ?? false {
                attrs[.strikethroughStyle] = NSUnderlineStyle
                    .single.rawValue
                // 删除线底（Web .moment-strikethrough，
                // J2-M03）：--fill-hover 底；横 2px
                // padding 在 NSAttributedString 无对
                // 应面，沿行内标记近似口径登记。
                attrs[.backgroundColor] = T.fillHoverUI
            }
            if let link = r["_link"] as? String, !link.isEmpty,
               let u = URL(string: link) {
                attrs[.link] = u
                // 链接色/线型（Web editor.css:116-118、
                // 294-295，J2-M01）：--md-link-color
                // 前景 + 单线；Wiki 另加虚线 pattern。
                // 线厚 0.08em / offset 0.16em（Wiki
                // 0.18em）在 NSAttributedString 无对
                // 应面，登记近似。
                attrs[.foregroundColor] = T.linkBlueUI
                attrs[.underlineStyle] =
                    (r["wiki"] as? Bool ?? false)
                    ? NSUnderlineStyle.single.rawValue
                        | NSUnderlineStyle.patternDash.rawValue
                    : NSUnderlineStyle.single.rawValue
            }
            // 上下标（MD 预览 Sup/Sub 与脚注序号）：字号
            // 0.75 + 基线 ±0.35em（Web sup/sub 口径）。
            let sup = r["sup"] as? Bool ?? false
            let sub = r["sub"] as? Bool ?? false
            if sup || sub {
                let f = attrs[.font] as? UIFont ?? base
                attrs[.font] = UIFont(
                    descriptor: f.fontDescriptor,
                    size: f.pointSize * 0.75)
                attrs[.baselineOffset] =
                    (sup ? 1 : -1) * base.pointSize * 0.35
            }
            // 行内公式（J1/E5，Web .math-inline）：快照
            // 就绪 → NSTextAttachment 随文排（bounds 以
            // 基线下沉量对齐）；失败 → 红色原码（Web
            // .math-source #CC0000）；未就绪 → 原码占位
            // （mono、正文色），MathImageStore 就绪发
            // 布后预览面重渲换图。mathTex 只由 MdRender
            // 产生，编辑面 runs 无此键、不受影响。
            var text = t
            if let tex = r["mathTex"] as? String {
                switch MathImageStore.shared.entry(
                    tex: tex, fontSize: base.pointSize) {
                case .ready(let img, let descent):
                    let att = NSTextAttachment()
                    att.image = img
                    att.bounds = CGRect(
                        x: 0, y: -descent,
                        width: img.size.width,
                        height: img.size.height)
                    attrs[.attachment] = att
                    attrs[.font] = base
                    text = "\u{FFFC}"
                case .failed:
                    attrs[.font] = FontFactory.derivedMono(
                        pointSize: base.pointSize * 0.85,
                        weight: .regular)
                    attrs[.foregroundColor] = T.mathFailUI
                case .pending:
                    attrs[.font] = FontFactory.derivedMono(
                        pointSize: base.pointSize * 0.85,
                        weight: .regular)
                }
            }
            out.append(NSAttributedString(string: text,
                                          attributes: attrs))
        }
        if out.length == 0 {
            return NSAttributedString(
                string: "", attributes: [.font: base])
        }
        return out
    }

    static func runs(from attr: NSAttributedString,
                     base: UIFont,
                     suppressStrikethrough: Bool = false)
        -> [[String: Any]] {
        // 标记判定须扣除块基础字重：标题块 base 本身 bold，
        // 不扣会把全段误标 bold 写回数据（样式层≠标记层）。
        let baseTraits = base.fontDescriptor.symbolicTraits
        var out: [[String: Any]] = []
        let full = NSRange(location: 0, length: attr.length)
        attr.enumerateAttributes(in: full) { attrs, range, _ in
            let t = (attr.string as NSString)
                .substring(with: range)
            if t.isEmpty { return }
            var r: [String: Any] = ["text": t]
            if let f = attrs[.font] as? UIFont {
                let traits = f.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold)
                    && !baseTraits.contains(.traitBold) {
                    r["bold"] = true
                }
                if traits.contains(.traitItalic)
                    && !baseTraits.contains(.traitItalic) {
                    r["italic"] = true
                }
                if traits.contains(.traitMonoSpace) {
                    r["code"] = true
                }
            }
            if let u = attrs[.underlineStyle] as? Int, u != 0 {
                r["underline"] = true
            }
            if !suppressStrikethrough,
               let s = attrs[.strikethroughStyle] as? Int,
               s != 0 {
                r["strikethrough"] = true
            }
            if let link = attrs[.link] {
                if let u = link as? URL {
                    r["_link"] = u.absoluteString
                } else if let s = link as? String {
                    r["_link"] = s
                }
            }
            out.append(r)
        }
        return out
    }
}

// ── 自适应高度 UITextView（系统输入法组字） ─────────
/// 编辑器文本视图：粘贴先过分流（成卡判定），消费则
/// 不走原生粘贴（Web paste 口径）。
final class EditorTextView: UITextView {
    var onPasteText: ((String) -> Bool)?
    var onPasteImage: ((Data) -> Bool)?
    /// 入窗回调（补丁债偿还批一 A-1）：由
    /// BlockTextView 注入——新建篇初始落焦认领
    /// 的入窗单点。视图真入窗是认领的因果时刻
    /// （window != nil 保证），替代转场宿主旧
    /// 0.2s 定时重开门的近似兜底（已删）。
    var onDidMoveToWindow: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onDidMoveToWindow?()
        }
    }
    /// 跨块方向键导航的模型钩（BlockTextView 注入）：
    /// pressesBegan 先问 EditorModel.handleKey，消费
    /// 则默认光标移动不发生。
    weak var navEditor: EditorModel?
    var navBlockId: String?
    /// 硬件键盘 Shift 按压态（Shift+Enter 软换行判定；
    /// UITextViewDelegate 不带修饰键，只能在按键事件
    /// 层跟踪）。
    private(set) var shiftHeld = false

    /// 选区活动端推定（F-09 二期 xselExtend 的原生
    /// 端点源）：UITextView.selectedRange 不记方
    /// 向（哪端是扩展中的活动端），而 Web native-
    /// Ends 取 selection 的真实锚/焦——原生等价推
    /// 定 = 逐次选区变化中「未动的一端为锚、动端
    /// 为活动端」：从收拢光标长出选区时光标端即
    /// 锚；其后单端移动者为活动端；双端齐动（替
    /// 换式跳变）保持旧推定。程序化投递（落点/撤
    /// 销恢复选区）不经 textViewDidChangeSelection
    /// 回调、推定不更新——默认活动端在尾（初值
    /// true），与恢复选区的存储读法（location 起
    /// 向后延展）同口径。回调挂 Coordinator.text-
    /// ViewDidChangeSelection，与 xsel 在位无关恒
    /// 记（选区建立期 xsel 尚不在位）。
    private(set) var xselFocusAtEnd = true
    private var xselPrevSel = NSRange(location: NSNotFound,
                                      length: 0)

    func noteXSelSelection() {
        let cur = selectedRange
        if cur.length == 0 {
            xselFocusAtEnd = true
        } else if xselPrevSel.location != NSNotFound,
                  cur != xselPrevSel {
            if cur.location == xselPrevSel.location {
                xselFocusAtEnd = true
            } else if cur.location + cur.length
                        == xselPrevSel.location
                            + xselPrevSel.length {
                xselFocusAtEnd = false
            }
        }
        xselPrevSel = cur
    }

    // E2/F-12 单轨：系统撤销轨（UITextView 的
    // undoManager 摇一摇/系统手势撤销）钉 nil——
    // 撤销只走模型栈（EditorModel.undo/redo 漏
    // 斗），双轨并存会同一步撤两次或撤到幽灵态。
    override var undoManager: UndoManager? { nil }

    override init(frame: CGRect,
                  textContainer: NSTextContainer?) {
        super.init(frame: frame,
                   textContainer: textContainer)
        installUndoSwipes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installUndoSwipes()
    }

    /// 三指手势撤销/重做（F-12 菜单文案所宣称的
    /// 入口，此前从未接线）：左滑 = 撤销、右滑 =
    /// 重做，与菜单/Cmd+Z 同走模型漏斗（不经
    /// undoManager，无双轨）。
    private func installUndoSwipes() {
        let undoSwipe = UISwipeGestureRecognizer(
            target: self, action: #selector(undoSwipeFired))
        undoSwipe.direction = .left
        undoSwipe.numberOfTouchesRequired = 3
        addGestureRecognizer(undoSwipe)
        let redoSwipe = UISwipeGestureRecognizer(
            target: self, action: #selector(redoSwipeFired))
        redoSwipe.direction = .right
        redoSwipe.numberOfTouchesRequired = 3
        addGestureRecognizer(redoSwipe)
    }

    @objc private func undoSwipeFired() {
        navEditor?.undo()
    }

    @objc private func redoSwipeFired() {
        navEditor?.redo()
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        // F-09 一期：跨块选区在位时粘贴 = 整段替换
        // （Web paste 同位）——纯文本优先于图片分流
        // （替换本体在 Coordinator.handlePaste 的
        // xsel 支）；剪贴板无文本则清选后走下方常
        // 规分流（Web 无文本清 xsel 同口径）。
        if let ed = navEditor, ed.xsel != nil {
            if let s = pb.string, let onPasteText,
               onPasteText(s) {
                return
            }
            ed.clearXSel()
        }
        if let onPasteImage, let img = pb.image,
           let data = img.pngData()
               ?? img.jpegData(compressionQuality: 0.9),
           onPasteImage(data) {
            return
        }
        if let s = pb.string,
           let onPasteText, onPasteText(s) {
            return
        }
        super.paste(sender)
    }

    /// 复制/剪切（F-09 一期菜单面）：xsel 在位时走
    /// 虚拟选区（复制 = 选区文本写剪贴板、剪切 =
    /// 复制 + 整段删除，与 Cmd+C/X 同体）；不在位
    /// 放行系统块内行为。
    override func copy(_ sender: Any?) {
        if let ed = navEditor, ed.xsel != nil {
            if let t = ed.xselClipboardText(), !t.isEmpty {
                UIPasteboard.general.string = t
            }
            return
        }
        super.copy(sender)
    }

    override func cut(_ sender: Any?) {
        if let ed = navEditor, ed.xsel != nil {
            if let t = ed.cutXSelText(), !t.isEmpty {
                UIPasteboard.general.string = t
            }
            return
        }
        super.cut(sender)
    }

    /// 全选（F-09 一期菜单面）：升为全文虚拟选区
    /// （Web Cmd+A 同口径；源码态块内不触发、保
    /// 持块内全选）。无编辑器钩时放行系统行为。
    override func selectAll(_ sender: Any?) {
        if let ed = navEditor,
           !ed.isXSelSourceBlock(navBlockId ?? "") {
            ed.selectAllXSel()
            return
        }
        super.selectAll(sender)
    }

    override func canPerformAction(
        _ action: Selector, withSender sender: Any?) -> Bool {
        // xsel 在位时原生选区收拢于锚点（长度 0），
        // 系统默认不给复制/剪切项——选区面在位即放
        // 行，动作本体走上方覆写。
        if navEditor?.xsel != nil,
           action == #selector(copy(_:))
            || action == #selector(cut(_:)) {
            return true
        }
        return super.canPerformAction(action,
                                      withSender: sender)
    }

    override func pressesBegan(_ presses: Set<UIPress>,
                               with event: UIPressesEvent?) {
        if event?.modifierFlags.contains(.shift) == true {
            shiftHeld = true
        }
        // 方向键分发（斜杠面板/跨块导航）：模型消费
        // 的按键不调 super——UITextView 的默认按键处
        // 理（光标移动/选区扩展）随之不发生。
        if let navEditor, let navBlockId {
            for p in presses
            where navEditor.handleKey(self,
                                      blockId: navBlockId,
                                      press: p) {
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func touchesBegan(_ touches: Set<UITouch>,
                               with event: UIEvent?) {
        // 点按散目标列会话（Web pointerdown 口径）。
        navEditor?.resetArrowGoal()
        super.touchesBegan(touches, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>,
                               with event: UIPressesEvent?) {
        shiftHeld = event?.modifierFlags
            .contains(.shift) ?? false
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?) {
        shiftHeld = false
        super.pressesCancelled(presses, with: event)
    }
}

struct BlockTextView: UIViewRepresentable {
    @ObservedObject var block: BlockState
    var editor: EditorModel?
    /// 非空时本视图编辑的是该列表块的一个 list-item。
    var listParent: BlockState? = nil
    var onChange: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = EditorTextView()
        // 跨块导航注册：按键钩 + 弱注册表（落焦直达
        // 目标视图）；dismantle 时注销。
        tv.navEditor = editor
        tv.navBlockId = block.id
        editor?.registerTV(tv, blockId: block.id)
        installWindowClaim(tv)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(
            top: 2, left: 0, bottom: 2, right: 0)
        // 链接色（Web --md-link-color #005BBB/#72B7FF，
        // 线 1 #10；系统默认蓝与之不同）：值单源
        // T.linkBlueUI（fix_dark_mode_full 归令，此
        // 前内联 trait 闭包散写同值）。
        tv.linkTextAttributes = [
            .foregroundColor: T.linkBlueUI,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        tv.textContainer.lineFragmentPadding = 0
        // 字体类别自适应（fix_dynamic_type_follow）：
        // 纯字体面（font/typingAttributes）随类别自
        // 动缩放；attributed string 内的字体是构建
        // 快照、不在此列，由 epoch 重刷整串重建（见
        // updateUIView 的 epoch 支）。
        tv.adjustsFontForContentSizeCategory = true
        // 文本拖放 lift 关闭（0.9.49，定案
        // audit_drag_pickup_round3 五.1 二选一取「关
        // 闭」）：UITextView 自带的文本拖动交互自持长
        // 按识别器，其 lift 预览是 UI 接管而非单纯识
        // 别，并行放开也压不住；且块文本被拖出并非编
        // 辑器的行为面（Web 按压期以 user-select:none
        // 压选区、无块文本拖出路）。关闭后拾起路径上
        // 只剩选区长按一方，由引擎并行放开 + 拾起收
        // 敛选区（convergeSelectionOnPickup）覆盖。
        tv.textDragInteraction?.isEnabled = false
        tv.delegate = context.coordinator
        reloadContent(tv)
        // 粘贴分流（Web 口径）：裸 URL/内嵌媒体 URL 成卡。
        let coord = context.coordinator
        tv.onPasteText = { [weak tv] text in
            guard let tv else { return false }
            return coord.handlePaste(text: text, tv: tv)
        }
        tv.onPasteImage = { [weak tv] data in
            guard tv != nil else { return false }
            return coord.handlePasteImage(data: data)
        }
        return tv
    }

    /// 尺寸口径根治：按提议宽度量高并回告该宽度——旧路
    /// 靠外部 .frame(height:) + bounds 猜宽，UITextView
    /// 会按未折行文本报固有宽，把整页撑出屏幕（真机截
    /// 图实证：正文居中溢出、两侧被裁）。
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView tv: UITextView,
                      context: Context) -> CGSize? {
        let w = proposal.width
            ?? (UIScreen.main.bounds.width - 32)
        // TextKit 2 惰性布局：长文本 sizeThatFits 只统
        // 计已布局片段、回报偏小高度——内容总高被算小
        // 后 ScrollView 判定无可滚、超帧文本被裁（三
        // 线审计布局线定案）。量测前强制全量布局；
        // 同一文本+宽度只做一次（签名缓存），滚动期
        // 的重复量测不再反复全量布局。
        if let lm = tv.textLayoutManager {
            let sig = "\(Int(w))|"
                + "\(tv.textStorage.string.hashValue)"
            if context.coordinator.laidOutSig != sig {
                context.coordinator.laidOutSig = sig
                lm.ensureLayout(for: lm.documentRange)
            }
        }
        let h = tv.sizeThatFits(CGSize(
            width: w, height: .greatestFiniteMagnitude)).height
        // 记录只入 contentH（自守卫）：本函数回的
        // 是 UITextView 内容高、布局由返回值驱动；
        // 行盒高归行盒 GeometryReader 单点喂
        // height（fix_drag_pickup_quote_face 定
        // 案），此处再写 height 即双喂回潮。
        if abs(h - block.contentH) > 0.5 {
            DispatchQueue.main.async { block.contentH = h }
        }
        return CGSize(width: w, height: h)
    }

    /// 块正文基准色单点（fix_dark_mode_full）：引
    /// 用块走 quoteText、余走 textMain——同一值同
    /// 时喂三面：attributed 串的 run 前景（渲染真
    /// 源）、typingAttributes（键入新字的前景）、
    /// textColor（空串/光标期的兜底）。旧形态只
    /// 喂 textColor 一面，而该通道在 TextKit 2 承
    /// 载下不达已设置 attributedText 的渲染（深
    /// 色下正文恒黑的根因，定案见 Marks.attributed
    /// 头注）；非引用块 textColor 旧值 .label 亦
    /// 在此归一为 textMainUI（与 Web --text-main
    /// 同账，.label 纯黑/纯白为近似值）。
    static func baseColorUI(for block: BlockState)
        -> UIColor {
        block.type == "quote" ? T.quoteTextUI : T.textMainUI
    }

    /// 内容重灌单点（建场 / 内容变更 / 字体代次变更
    /// 三路共用）：按现行类别重算基准字体并整串重建。
    /// attributed string 内的字体是构建时快照，类别
    /// 变更后唯有整串重建才换档（fix_dynamic_type_
    /// follow）；颜色口径见 baseColorUI 头注。
    func reloadContent(_ tv: UITextView) {
        let base = Marks.baseFont(for: block)
        let baseColor = Self.baseColorUI(for: block)
        tv.font = base
        tv.typingAttributes = [
            .font: base,
            .foregroundColor: baseColor,
        ]
        tv.textColor = baseColor
        tv.attributedText = Marks.withRhythm(
            Marks.attributed(runs: block.runs, base: base,
                             baseColor: baseColor),
            block: block)
        applyDoneStyle(tv)
    }

    /// 待办完成态（Web 口径）：文字删除线 + 变灰——仅显
    /// 示层，回写时由 suppressStrikethrough 扣除，不落盘。
    private func applyDoneStyle(_ tv: UITextView) {
        guard block.type == "todo", block.checked,
              tv.attributedText.length > 0 else { return }
        let m = NSMutableAttributedString(
            attributedString: tv.attributedText)
        let full = NSRange(location: 0, length: m.length)
        m.addAttribute(.strikethroughStyle, value: 1,
                       range: full)
        // 完成态文字色单源 T.doneTextUI（Web
        // --md-text-muted，线 1 #15；fix_dark_mode_
        // full 归令，此前内联 trait 闭包散写同值）。
        m.addAttribute(.foregroundColor,
                       value: T.doneTextUI,
                       range: full)
        tv.attributedText = m
    }

    /// 段内分段着色（F-09 二期，Web paintXsel 段
    /// 级口径）：本块选段经 textStorage 属性层涂
    /// T.xselHighlightUI——CSS Highlight 只涂字形
    /// 段、行面留白不涂，与行级整行着色（一期全
    /// 选态近似）分工：文本块一律走本面、原子行
    /// 整行走 BlockRow 行面（xselRowCovered）。
    /// 涂前快照段内既有背景（Marks 的行内代码/
    /// 高亮背景同用 .backgroundColor 通道），收
    /// 段/移段时逐段恢复，不整段剔除、不伤标记
    /// 底。内容重灌（reloadContent 任一路径）后
    /// 属性层已是新串、本涂层不在——以「段首实
    /// 测背景 ≠ 令牌色」自愈判定重涂（不依赖各
    /// 重灌点逐个通知）。updateUIView 每轮收尾
    /// 调用（组字中除外：组字开始选区已收拢、段
    /// 恒空，且不扰 marked 呈现）。
    private func refreshXSelHighlight(
        _ tv: UITextView, coordinator: Coordinator) {
        let seg = editor?.xselSegment(forBlockId: block.id)
        let want: NSRange? = seg.flatMap { s in
            s.to > s.from
                ? NSRange(location: s.from,
                          length: s.to - s.from)
                : nil
        }
        let storage = tv.textStorage
        let token = T.xselHighlightUI
        func painted(_ r: NSRange) -> Bool {
            guard r.length > 0, r.location < storage.length
            else { return false }
            let c = storage.attribute(
                .backgroundColor, at: r.location,
                effectiveRange: nil) as? UIColor
            return c?.isEqual(token) == true
        }
        if coordinator.xselSegRange == want,
           want == nil || painted(want!) {
            return
        }
        // 收旧段：本涂层仍在才恢复快照（已被重灌
        // 冲掉时新串自带正确标记底，不恢复）。
        if let old = coordinator.xselSegRange {
            if painted(old) {
                storage.beginEditing()
                storage.removeAttribute(.backgroundColor,
                                        range: old)
                for (r, c) in coordinator.xselSegSaved {
                    if let c {
                        storage.addAttribute(
                            .backgroundColor, value: c,
                            range: r)
                    }
                }
                storage.endEditing()
            }
            coordinator.xselSegRange = nil
            coordinator.xselSegSaved = []
        }
        if let want, want.location + want.length
                <= storage.length {
            var saved: [(NSRange, UIColor?)] = []
            storage.enumerateAttribute(
                .backgroundColor, in: want, options: []
            ) { v, r, _ in
                saved.append((r, v as? UIColor))
            }
            storage.addAttribute(.backgroundColor,
                                 value: token, range: want)
            coordinator.xselSegRange = want
            coordinator.xselSegSaved = saved
        }
    }

    static func dismantleUIView(_ tv: UITextView,
                                coordinator: Coordinator) {
        if let etv = tv as? EditorTextView {
            etv.navEditor?.unregisterTV(etv)
            etv.navEditor = nil
            etv.navBlockId = nil
        }
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // 导航钩保鲜（editor 实例/块身份随重组更新）。
        if let etv = tv as? EditorTextView {
            etv.navEditor = editor
            etv.navBlockId = block.id
            editor?.registerTV(etv, blockId: block.id)
            installWindowClaim(etv)
        }
        let key = "\(block.type)-\(block.level)-"
            + "\(block.nodeVersion)"
        let typeChanged = context.coordinator.lastTypeKey != key
        if typeChanged {
            context.coordinator.lastTypeKey = key
        }
        // 拆/并块后 nodeVersion 变化：即便本视图还持焦点
        // 也要按新 runs 重载（否则旧全文残留在已拆块里）。
        let versionChanged =
            context.coordinator.lastVersion != block.nodeVersion
        if versionChanged {
            context.coordinator.lastVersion = block.nodeVersion
        }
        // 新建篇初始落焦认领：首个文本块的视图认领，
        // 但须先过转场门（0.9.50 呈现重构，
        // fix_transition_refactor）：0.9.46–0.9.49 的
        // 安装帧认领让键盘动画在 push 第 0 帧即起、与
        // 转场全程重叠，真机呈接力式两段过渡（0.9.48
        // Diag 实证 kb 于 dest 后 36–67ms 起）。现呈
        // 现由 EditorTransitionHost 以 UIKit push 独占：
        // 编辑器转场前已构建，宿主在转场 completion
        // 后 openFocusGate 并以 tick 触发本轮更新，认
        // 领在此发生——键盘在页面落定后单独升起，任
        // 一时刻只有一个动画。落点口径不变（首个文本
        // 块、光标在块首）；认领走 claimInitialFocus
        // （成功校验 + 有界重试，见其注释）。认领尝
        // 试单点 attemptInitialClaim 另有入窗触发面：
        // 本块视图真入窗（didMoveToWindow）时同点重
        // 试——首拍更新未达本视图/视图尚未入窗的情
        // 形由因果事件兜底，宿主旧 0.2s 定时重开门
        // 已删（补丁债偿还批一 A-1）。
        let initialClaim = attemptInitialClaim(tv)
        if !initialClaim, let ed = editor,
                  ed.focusBlockId == block.id,
                  !tv.isFirstResponder {
            // 聚焦请求消费（拆块落新块、并块落接合
            // 处等）。
            tv.becomeFirstResponder()
            let caret: Int
            if let off = ed.pendingCaretOffset {
                caret = min(off, tv.text.count)
                DispatchQueue.main.async {
                    ed.pendingCaretOffset = nil
                }
            } else if ed.focusCaretEnd {
                caret = tv.text.count
            } else {
                caret = 0
            }
            // E2/F-11：选区长度随落点一并投递（撤销
            // 恢复的非零选区；其余路径恒 0 = 纯光标）。
            tv.selectedRange = NSRange(
                location: caret,
                length: min(ed.pendingSelectionLength,
                            tv.text.count - caret))
            DispatchQueue.main.async {
                ed.pendingSelectionLength = 0
                if ed.focusBlockId == block.id {
                    ed.focusBlockId = nil
                }
            }
        }
        // 已聚焦块的光标落点请求（斜杠行内命令/转块后
        // 落 token 起点）：视图已持焦点时直接落选区。
        if let ed = editor, ed.focusBlockId == block.id,
           let off = ed.pendingCaretOffset,
           tv.isFirstResponder {
            let caretNow = min(off, tv.text.count)
            tv.selectedRange = NSRange(
                location: caretNow,
                length: min(ed.pendingSelectionLength,
                            tv.text.count - caretNow))
            DispatchQueue.main.async {
                ed.pendingCaretOffset = nil
                ed.pendingSelectionLength = 0
                if ed.focusBlockId == block.id {
                    ed.focusBlockId = nil
                }
            }
        }
        // 字体代次（fix_dynamic_type_follow）：系统
        // 类别变更经 FontHub.epoch 到达——attributed
        // 快照的重建门此前只认内容/类型变化，类别变
        // 更永不触发重建、编辑器正文定格旧档（0.9.58
        // 真机实报的整类根因）。epochChanged 并入重
        // 建门：未持焦块即时整串重建；持焦块不打断
        // 编辑（组字/选区安全），只先换 font/typing-
        // Attributes 并登记 pendingFontRefresh，失
        // 焦时由 Coordinator 补整串重建。
        let epoch = FontHub.shared.epoch
        let epochChanged =
            context.coordinator.fontEpoch != epoch
        if (tv.text != block.text || typeChanged
                || epochChanged)
            && tv.markedTextRange == nil
            && (!tv.isFirstResponder || versionChanged) {
            reloadContent(tv)
            context.coordinator.fontEpoch = epoch
            context.coordinator.pendingFontRefresh = false
        } else if epochChanged && tv.isFirstResponder
                    && tv.markedTextRange == nil {
            // epoch 登记同置于处理点：组字中两支都
            // 不入、epoch 保持未消费，组字结束后的
            // 更新轮次再处理（防该块永久漏刷）。
            context.coordinator.fontEpoch = epoch
            let base = Marks.baseFont(for: block)
            tv.font = base
            // typingAttributes 与 reloadContent 同
            // 构成（字体 + 基准色，fix_dark_mode_
            // full）：持焦块类别变更时不整串重建，
            // 键入新字的前景靠此面跟上。
            tv.typingAttributes = [
                .font: base,
                .foregroundColor: Self.baseColorUI(
                    for: block),
            ]
            context.coordinator.pendingFontRefresh = true
        }
        // F-09 二期段内分段着色刷新（状态机见
        // refreshXSelHighlight）：置于内容重灌判
        // 定之后——同轮重灌的新串由其自愈判定补
        // 涂；组字中不入（见该注）。
        if tv.markedTextRange == nil {
            refreshXSelHighlight(
                tv, coordinator: context.coordinator)
        }
    }

    /// 初始落焦认领的尝试单点（补丁债偿还批一
    /// A-1）：门开 + 意图在 + 本块为首个文本块，
    /// 三条件齐备才投递认领，返回是否已投递
    /// （updateUIView 据此让行聚焦请求消费支）。
    /// 两个触发面共用本体：更新轮（宿主开门
    /// tick 驱动）与块视图入窗回调（真入窗的因
    /// 果时刻）——后者替代宿主旧 0.2s 定时重开
    /// 门：首拍更新未达本视图时，视图入窗瞬间
    /// 在此补认领，window != nil 由回调点保证。
    @discardableResult
    private func attemptInitialClaim(
        _ tv: UITextView) -> Bool {
        guard let ed = editor,
              ed.wantsInitialFocus, ed.focusGateOpen,
              ed.blocks.first(where: { $0.isText })?.id
                == block.id
        else { return false }
        claimInitialFocus(tv, ed: ed)
        return true
    }

    /// 入窗认领接线（A-1）：把本 representable 的
    /// 认领尝试挂到 EditorTextView 的 didMoveTo-
    /// Window 回调点；make/update 两处同挂（值随
    /// 每轮更新保鲜）。
    private func installWindowClaim(_ tv: UITextView) {
        guard let etv = tv as? EditorTextView
        else { return }
        etv.onDidMoveToWindow = { [weak etv] in
            guard let etv else { return }
            self.attemptInitialClaim(etv)
        }
    }

    /// 新建篇初始落焦认领（0.9.48 补成功校验，治第
    /// 二轮排查 S4 脆弱点）：旧实现尝试前先清
    /// wantsInitialFocus 旗、becomeFirstResponder 返回
    /// 值直接丢弃——首轮 updateUIView 时视图尚未入
    /// 窗则认领静默丢失、永不重试（失败形态是「开
    /// 新篇无键盘」）。现口径：返回值入账（CREATE
    /// claim 行记 ok/入窗位），成功才清旗并走原落
    /// 点/计时收口；失败不清旗、下一主线程回合有
    /// 界重试（总尝试 ≤3），耗尽才清旗并记 ok=0。
    private func claimInitialFocus(_ tv: UITextView,
                                   ed: EditorModel) {
        if tv.isFirstResponder {
            ed.wantsInitialFocus = false
            return
        }
        let ok = tv.becomeFirstResponder()
        if ok {
            ed.wantsInitialFocus = false
            ed.recordCreateClaim(ok: true,
                                 inWindow: tv.window != nil)
            ed.logCreateFocusTiming()
            let caret: Int
            if let off = ed.pendingCaretOffset {
                caret = min(off, tv.text.count)
                DispatchQueue.main.async {
                    ed.pendingCaretOffset = nil
                }
            } else if ed.focusCaretEnd {
                caret = tv.text.count
            } else {
                caret = 0
            }
            tv.selectedRange = NSRange(location: caret,
                                       length: 0)
        } else {
            ed.createClaimAttempts += 1
            if ed.createClaimAttempts >= 3 {
                ed.wantsInitialFocus = false
                ed.recordCreateClaim(
                    ok: false, inWindow: tv.window != nil)
            } else {
                DispatchQueue.main.async { [weak tv] in
                    guard let tv, ed.wantsInitialFocus
                    else { return }
                    self.claimInitialFocus(tv, ed: ed)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BlockTextView
        var lastTypeKey = ""
        var lastVersion = -1
        /// 已对齐的字体代次（FontHub.epoch）：-1 =
        /// 未对齐，首轮更新即按现行类别重灌一次
        /// （与建场同档、幂等）。
        var fontEpoch = -1
        /// 持焦期间类别变更的待补重建旗：失焦时由
        /// textViewDidEndEditing 消费（整串重建）。
        var pendingFontRefresh = false
        /// F-09 二期分段着色状态：当前已涂段
        /// （UTF-16）与涂前段内既有背景的快照
        /// （收段时逐段恢复——Marks 自有背景[行
        /// 内代码/高亮等]不整段剔除，见
        /// refreshXSelHighlight）。
        var xselSegRange: NSRange?
        var xselSegSaved: [(NSRange, UIColor?)] = []
        /// 已做全量布局的文本签名（内容+宽度）：未变
        /// 则跳过 ensureLayout，防滚动期反复全量布局。
        var laidOutSig = ""
        init(_ p: BlockTextView) { parent = p }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.editor?.editingBlockId = parent.block.id
            // 进入文本编辑即散原子块选中态（F-08，
            // Web clearSelect 同口径）。
            parent.editor?.selectedBlockId = nil
            // 文本编辑会话开始压一帧历史（撤销回到会话始）。
            parent.editor?.pushHistory()
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            // 字体待补重建（fix_dynamic_type_follow）：
            // 持焦期间类别变更只换了 font/typingAttr-
            // ibutes，失焦后在此整串重建补齐快照字体
            // （此时已非第一响应者、组字必已收口）。
            if pendingFontRefresh {
                pendingFontRefresh = false
                parent.reloadContent(tv)
            }
            if parent.editor?.editingBlockId == parent.block.id {
                parent.editor?.editingBlockId = nil
                // 失焦转预览时点补尾随空段（Web 口径）。
                parent.editor?.materializeMdTrails()
            }
        }

        /// 撤销检查点馈入（E2/F-10 爆发合并）：普通
        /// 文本放行点在变更落模型前调——快照取本键
        /// 前的模型态、选区取被替换范围（字符口径
        /// 在 EditorModel.noteTextWillChange 内换
        /// 算）。结构支（拆/并/插行）走各自 op 的
        /// pushHistory，不经此面。replacement 随行
        /// 穿入：模型侧据「非空范围被非空文本替
        /// 换」判选区替换断链（纯删除 replacement
        /// 为空、不在此列）。
        private func feedUndoCheckpoint(
            _ tv: UITextView, _ range: NSRange,
            replacement: String) {
            parent.editor?.noteTextWillChange(
                blockId: parent.block.id,
                text: tv.text ?? "", range: range,
                replacement: replacement)
        }

        func textView(_ tv: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard let ed = parent.editor,
                  tv.markedTextRange == nil,
                  parent.block.isText
                    || parent.block.type == "list-item"
            else { return true }
            // F-09 一期：跨块选区在位时一切文本变更
            // 经选区替换漏斗（Web keydown 接管的软件
            // 键盘等价面）——回车 = enter 替换，其余
            // （键入/删除/多行插入）= 整段替换；组字
            // 中不达此处（上方 marked 守卫 + 组字开
            // 始收拢双保险），斜杠等块内流程亦不达
            // （选区在位时击键先归替换，Web 同序）。
            if ed.xsel != nil {
                if text == "\n" {
                    ed.replaceXSel(text: "", enter: true)
                } else {
                    ed.replaceXSel(text: text, enter: false)
                }
                return false
            }
            let full = tv.attributedText
                ?? NSAttributedString()
            let loc = min(range.location, full.length)
            let end = min(range.location + range.length,
                          full.length)
            let before = full.attributedSubstring(
                from: NSRange(location: 0, length: loc))
            let after = full.attributedSubstring(
                from: NSRange(location: end,
                              length: full.length - end))
            if text.contains("\n") {
                if parent.block.type == "codeBlock" {
                    // 代码块内换行是正文（E2 检查点：
                    // 普通文本放行前馈入撤销合并）。
                    feedUndoCheckpoint(
                        tv, range, replacement: text)
                    return true
                }
                if text == "\n",
                   (tv as? EditorTextView)?.shiftHeld
                       == true {
                    // Shift+Enter 软换行（Web 口径）：块内
                    // 换行不拆块，放行原生插入（E2 检查
                    // 点同代码块支）。
                    feedUndoCheckpoint(
                        tv, range, replacement: text)
                    return true
                }
                // 回车拆块 / 粘贴多行拆块（E17）：统一走
                // insertLines（列表项在列表内续项）。
                let lines = text
                    .replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: "\n")
                if text == "\n" && parent.listParent == nil
                    && (parent.block.type == "heading"
                        || parent.block.type == "callout") {
                    // 标题/Callout 回车不拆文本（Web 口径）：
                    // 整段保留、其后插空段落。
                    ed.headingEnter(parent.block)
                } else if text == "\n"
                    && parent.listParent == nil
                    && (parent.block.type == "todo"
                        || parent.block.type == "quote")
                    && parent.block.text.isEmpty {
                    // T-4：空待办/空引用回车 = 自身转
                    // 段落退出（Web 调优口径，不再产一
                    // 个空同型块）。
                    ed.exitEmptyBlock(parent.block)
                } else if text == "\n"
                    && parent.listParent == nil {
                    ed.splitBlock(parent.block, before: before,
                                  after: after)
                } else if text == "\n",
                          let list = parent.listParent,
                          parent.block.text.isEmpty {
                    // 空项回车 = 退出列表（Web 口径）。
                    ed.exitListItem(list: list,
                                    item: parent.block)
                } else {
                    ed.insertLines(parent.block,
                                   listParent: parent.listParent,
                                   before: before, lines: lines,
                                   after: after)
                }
                return false
            }
            if text.isEmpty && range.location == 0
                && range.length == 0 {
                // 段首退格并块（列表项走列表口径）。
                if let list = parent.listParent {
                    ed.mergeListItemBackward(
                        list: list, item: parent.block)
                } else {
                    ed.mergeBlockBackward(parent.block)
                }
                return false
            }
            if text.isEmpty && range.length == 0
                && range.location > 0
                && range.location
                    == (tv.text as NSString).length
                && ed.slashBlockId == nil {
                // 块末前向删除并块（B-05，与段首退格
                // 对称）：前向删除在块末的空变更即此
                // 形（块内删下一字是 (loc,1) 不入本
                // 支）；斜杠面板在位时不并块（按键面
                // handleKey 同守卫）。
                if let list = parent.listParent {
                    ed.mergeListItemForward(
                        list: list, item: parent.block)
                } else {
                    ed.mergeBlockForward(parent.block)
                }
                return false
            }
            // 普通文本放行（键入/删除/粘贴文本）：E2
            // 检查点——变更落模型前馈入撤销合并。
            feedUndoCheckpoint(
                tv, range, replacement: text)
            return true
        }

        /// 粘贴图片成块（E17）：当前块后插图片块（仅顶层）。
        func handlePasteImage(data: Data) -> Bool {
            guard parent.listParent == nil,
                  let editor = parent.editor else {
                return false
            }
            editor.insertPastedImage(block: parent.block,
                                     data: data)
            return true
        }

        /// 粘贴分流入口：按当前选区切 before/after 交给
        /// EditorModel 判成卡（仅顶层文本块）。
        func handlePaste(text: String, tv: UITextView)
            -> Bool {
            // F-09 一期：跨块选区在位时粘贴 = 整段
            // 替换（Web paste 同位，先于成卡分流；
            // 锚点为列表项时亦然，Web 任意可编辑宿
            // 主同口径）。
            if let editor = parent.editor,
               editor.xsel != nil {
                editor.replaceXSel(text: text, enter: false)
                return true
            }
            guard parent.listParent == nil,
                  let editor = parent.editor else {
                return false
            }
            let base = Marks.baseFont(for: parent.block)
            let suppress = parent.block.type == "todo"
                && parent.block.checked
            let full = tv.attributedText
                ?? NSAttributedString()
            let sel = tv.selectedRange
            let beforeAttr = full.attributedSubstring(
                from: NSRange(location: 0,
                              length: sel.location))
            let afterStart = sel.location + sel.length
            let afterAttr = full.attributedSubstring(
                from: NSRange(location: afterStart,
                              length: full.length - afterStart))
            return editor.handlePaste(
                block: parent.block, text: text,
                beforeRuns: Marks.runs(
                    from: beforeAttr, base: base,
                    suppressStrikethrough: suppress),
                afterRuns: Marks.runs(
                    from: afterAttr, base: base,
                    suppressStrikethrough: suppress))
        }

        func textViewDidChange(_ tv: UITextView) {
            // 文本变更散目标列会话（Web input 口径）。
            parent.editor?.resetArrowGoal()
            // 组字守卫（F-01，Web 组字期模型冻结口
            // 径）：marked 中间态不入模型——runs/text
            // 不写、不排保存（onChange 即 scheduleSave
            // 的 0.6s 防抖落盘）、不触发斜杠扫描；与
            // 本文件既有三处组字守卫（shouldChange 的
            // 结构拦截、方向键不消费、updateUIView 禁
            // 反写）同口径补齐最后一面。marked 清除
            // 后一拍（提交/取消的 didChange）走下方
            // 全量同步，终态同源无残留（提交瞬间全
            // 量重算 runs 的既有口径不变）。
            if tv.markedTextRange != nil {
                // F-09 一期组字收拢（Web composition-
                // start 同位，挂同一组字判定点、不另
                // 起守卫）：组字开始即收拢跨块选区到
                // 焦点端——组字文本只落焦点端块的原
                // 生面，绝不经 replaceRange（收拢本
                // 体 nil 守卫、逐 marked 更新重复调
                // 无副作用）。
                parent.editor?.collapseXSel()
            }
            guard tv.markedTextRange == nil else { return }
            parent.block.runs = Marks.runs(
                from: tv.attributedText,
                base: Marks.baseFont(for: parent.block),
                suppressStrikethrough: parent.block.type
                    == "todo" && parent.block.checked)
            parent.block.text = tv.text
            parent.onChange()
            // 斜杠面板触发/过滤跟随文本与选区（块内任意
            // 位置 token，含列表项；判定在 EditorModel）。
            // 横向锚（J2-F18）：选区末端光标矩形换算到
            // 窗口 X，随本次更新一并交给 updateSlash。
            var caretX: CGFloat? = nil
            var caretLineTop: CGFloat? = nil
            var caretLineBottom: CGFloat? = nil
            if let end = tv.position(
                from: tv.beginningOfDocument,
                offset: tv.selectedRange.location
                    + tv.selectedRange.length) {
                // 同一光标矩形一并给纵向行锚（B-03：
                // 行上下缘窗口 Y，面板定顶吃光标行）。
                let rect = tv.convert(
                    tv.caretRect(for: end), to: nil)
                caretX = rect.minX
                caretLineTop = rect.minY
                caretLineBottom = rect.maxY
            }
            parent.editor?.updateSlash(
                for: parent.block, selUTF16: tv.selectedRange,
                caretX: caretX, caretLineTop: caretLineTop,
                caretLineBottom: caretLineBottom)
            // 智能前缀尾扫（F-02，Web inputSync 消息
            // 尾 apply_smart_prefix 同位）：文本落模
            // 型后扫全 doc 转首个命中段落；组字期已
            // 在上方守卫早退、不会以拼音中间态命中。
            parent.editor?.applySmartPrefixIfNeeded()
        }

        // F-09 一期失效对账（Web selectionchange 对
        // 账同构，挂既有选区变化回调面）：原生选区
        // 变化即与跨块选区对账——组字先收拢、非空
        // 选区或落点离锚点即清选（判定本体在桥接
        // 层 noteXSelNativeSelection，单点）。二期
        // 活动端跟踪同挂此回调、先行记（与 xsel 在
        // 位无关，推定本体在 EditorTextView.
        // noteXSelSelection）。
        func textViewDidChangeSelection(_ tv: UITextView) {
            (tv as? EditorTextView)?.noteXSelSelection()
            guard let ed = parent.editor, ed.xsel != nil
            else { return }
            ed.noteXSelNativeSelection(
                blockId: parent.block.id,
                location: tv.selectedRange.location,
                length: tv.selectedRange.length,
                marked: tv.markedTextRange != nil)
        }
    }
}

// ── 图片块：fileId 走 FFI 附件字节，URL 走网络 ──────
/// 媒体解码管线单点（审计批 3 收口：AUD-E-04/
/// D-06/D-07）：解码、共享缓存、帧时长三件在
/// 此一处，ImageLoader.publish 是唯一调用方
/// （SVG 嗅探分流在其前）。旧 decodeImage 自
/// 由函数（全尺寸逐帧、帧时长只读 GIF 字典、
/// 无缓存——同图在列表/编辑/图片页多面各自全
/// 尺寸重解）整体替换为本处，不留旧路。
// APNG 属性字典键：本工具链 SDK 的
// CGImageProperties.h 缺 kCGImageProperty-
// APNGDictionary 本体的 extern 声明（其
// DelayTime/UnclampedDelayTime 等子键都在、
// 唯字典键被漏）——按 Apple 文档常量值
// "{APNG}" 自备同名同值定义，运行时
// ImageIO 回的帧属性字典即以此串为键。
// SDK 补齐该声明后删本节、改回系统常量。
private let kCGImagePropertyAPNGDictionary: CFString =
    "{APNG}" as CFString

enum MediaDecode {
    /// 块内呈现面降采样上限（纯核心口径的
    /// CGFloat 面，MediaDecodePolicy 单点）。
    static var blockMaxPixel: CGFloat {
        CGFloat(MediaDecodePolicy.blockMaxPixel)
    }

    /// 共享解码缓存：键 = 源键 + 尺寸桶（同源
    /// 不同桶各存一份——图片页全尺寸与块内降
    /// 采样不互覆）；附件字节按 id 写一次读多
    /// 次、内容不可变，故键不含内容哈希。cost
    /// 按解码后像素估算，总量上限护内存。
    private static let cache:
        NSCache<NSString, UIImage> = {
            let c = NSCache<NSString, UIImage>()
            c.totalCostLimit = 96 * 1024 * 1024
            return c
        }()

    private static func cacheKey(
        _ key: ImageSourceKey, maxPixel: CGFloat?
    ) -> NSString {
        let src = key.fileId
            ?? key.urlString ?? "none"
        let bucket = maxPixel.map { Int($0) } ?? 0
        return "\(src)|\(bucket)" as NSString
    }

    /// 汇合点：缓存命中直出（data 不再解码）；
    /// 未命中解码后存入（失败不存——失败行由
    /// loader 沿旧口径记）。
    static func image(for key: ImageSourceKey,
                      data: Data,
                      maxPixel: CGFloat?) -> UIImage? {
        let ck = cacheKey(key, maxPixel: maxPixel)
        if let hit = cache.object(forKey: ck) {
            return hit
        }
        guard let img = decode(data,
                               maxPixel: maxPixel)
        else { return nil }
        let cost = Int(img.size.width
            * img.size.height
            * img.scale * img.scale * 4)
        cache.setObject(img, forKey: ck,
                        cost: cost)
        return img
    }

    /// 解码本体（用户 2026-11-26 裁定补 GIF 播
    /// 放的逐帧路在此延续）：多帧逐帧组
    /// animatedImage、单帧常规路；带 maxPixel
    /// 时逐帧/单帧均走 ImageIO 缩略图路（解码
    /// 即降采样，不先全尺寸解码再缩——AUD-
    /// E-04/D-06 的护栏本体）。
    static func decode(_ data: Data,
                       maxPixel: CGFloat?) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(
            data as CFData, nil)
        else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else {
            return stillImage(src, data: data,
                              maxPixel: maxPixel)
        }
        var frames: [UIImage] = []
        var total: TimeInterval = 0
        for i in 0..<count {
            guard let cg = frameImage(
                src, index: i, maxPixel: maxPixel)
            else { continue }
            frames.append(UIImage(cgImage: cg))
            total += frameDelay(
                CGImageSourceCopyPropertiesAtIndex(
                    src, i, nil) as? [String: Any])
        }
        guard frames.count > 1 else {
            return stillImage(src, data: data,
                              maxPixel: maxPixel)
        }
        return UIImage.animatedImage(with: frames,
                                     duration: total)
    }

    private static func frameImage(
        _ src: CGImageSource, index: Int,
        maxPixel: CGFloat?) -> CGImage? {
        if let maxPixel,
           let cg = thumbnail(src, index: index,
                              maxPixel: maxPixel) {
            return cg
        }
        return CGImageSourceCreateImageAtIndex(
            src, index, nil)
    }

    private static func stillImage(
        _ src: CGImageSource, data: Data,
        maxPixel: CGFloat?) -> UIImage? {
        if let maxPixel,
           let cg = thumbnail(src, index: 0,
                              maxPixel: maxPixel) {
            return UIImage(cgImage: cg)
        }
        return UIImage(data: data)
    }

    private static func thumbnail(
        _ src: CGImageSource, index: Int,
        maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways:
                true,
            kCGImageSourceCreateThumbnailWithTransform:
                true,
            kCGImageSourceThumbnailMaxPixelSize:
                maxPixel,
            kCGImageSourceShouldCacheImmediately:
                true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            src, index, opts as CFDictionary)
    }

    /// 帧时长取数面：GIF/APNG/WebP 三字典的
    /// unclamped → clamped 原值依次呈纯核心
    /// 裁定（AUD-D-07：旧实现只读 GIF 字典，
    /// APNG/动态 WebP 恒缺省 0.1 的口子在此
    /// 收口；裁定规则在 MediaFrameTiming）。
    private static func frameDelay(
        _ props: [String: Any]?) -> TimeInterval {
        guard let props else {
            return MediaFrameTiming.defaultDelay
        }
        func pick(_ dictKey: CFString,
                  _ unclamped: CFString,
                  _ clamped: CFString) -> [Double?] {
            guard let d = props[dictKey as String]
                as? [String: Any] else { return [] }
            return [d[unclamped as String] as? Double,
                    d[clamped as String] as? Double]
        }
        let candidates =
            pick(kCGImagePropertyGIFDictionary,
                 kCGImagePropertyGIFUnclampedDelayTime,
                 kCGImagePropertyGIFDelayTime)
            + pick(kCGImagePropertyAPNGDictionary,
                   kCGImagePropertyAPNGUnclampedDelayTime,
                   kCGImagePropertyAPNGDelayTime)
            + pick(kCGImagePropertyWebPDictionary,
                   kCGImagePropertyWebPUnclampedDelayTime,
                   kCGImagePropertyWebPDelayTime)
        return MediaFrameTiming.resolve(
            candidates: candidates)
    }
}

/// 块内动图承载（AUD-D-01 根治）：SwiftUI
/// Image 只呈首帧——管线组好的 animated-
/// Image 到呈现面被弃，块内 GIF 恒静
/// 止（与 Web <img> 全面播分叉）。块内各面
/// （图块/gallery 瓦/图文卡/MD 图/附件图/首
/// 页封面）的图片本体统一走本承载：UIImage-
/// View 驱动逐帧；布局语义按 mode 复刻原
/// SwiftUI 口径——fill = 提议尺寸直填（单维
/// 缺失按图比例补、全缺回自然尺寸），fit =
/// 自然比例 contain、不放大（可选高上限）。
/// 非交互：点按/长按手势恒挂容器面，与旧
/// Image 的被动角色一致，不吞手势。
struct AnimImageView: UIViewRepresentable {
    let image: UIImage
    var mode: UIView.ContentMode = .scaleAspectFill
    /// fit 口径的附加高钳（图块 668、MD 图
    /// nil = 只受提议高与自然高约束）。
    var fitMaxHeight: CGFloat? = nil

    func makeUIView(context: Context) -> UIImageView {
        let iv = UIImageView(image: image)
        iv.contentMode = mode
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = false
        return iv
    }

    func updateUIView(_ iv: UIImageView,
                      context: Context) {
        if iv.image !== image { iv.image = image }
        iv.contentMode = mode
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UIImageView,
                      context: Context) -> CGSize? {
        let nat = image.size
        guard nat.width > 0, nat.height > 0
        else { return .zero }
        switch mode {
        case .scaleAspectFit:
            var limitW = nat.width
            if let w = proposal.width {
                limitW = min(limitW, w)
            }
            var limitH = fitMaxHeight ?? .infinity
            if let h = proposal.height {
                limitH = min(limitH, h)
            }
            let scale = min(1, limitW / nat.width,
                            limitH / nat.height)
            return CGSize(width: nat.width * scale,
                          height: nat.height * scale)
        default:
            switch (proposal.width, proposal.height) {
            case let (w?, h?):
                return CGSize(width: w, height: h)
            case let (w?, nil):
                return CGSize(
                    width: w,
                    height: w * nat.height / nat.width)
            case let (nil, h?):
                return CGSize(
                    width: h * nat.width / nat.height,
                    height: h)
            case (nil, nil):
                return nat
            }
        }
    }
}

final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    // 身份键控闸门（fix_image_card_load）：取代旧
    // started 一次性闩锁——源键未变才跳过、键变
    // 即复位重载（决策纯核心在 MomentImageLoad
    // .swift，本类只执行与发布）。loadSerial 为
    // 代际号：键变后旧键在途结果回主线程时已过
    // 期、deliver 单点弃之，防换图后旧图回闪。
    private var gate = ImageLoadGate()
    private var loadSerial = 0
    /// 本轮加载的降采样上限（审计批 3）：块内
    /// 面呈 MediaDecode.blockMaxPixel、图片页
    /// 不传（nil = 全尺寸）；与 serial 同拍更
    /// 新、publish 汇合点消费，作解码与缓存的
    /// 尺寸桶。
    private var activeMaxPixel: CGFloat?

    func load(block: BlockState, library: Library,
              maxPixel: CGFloat? = nil) {
        load(fileId: block.fileId, urlString: block.imageURL,
             library: library, maxPixel: maxPixel)
    }

    func load(fileId: String?, urlString: String?,
              library: Library,
              maxPixel: CGFloat? = nil) {
        let decision = gate.offer(fileId: fileId,
                                  urlString: urlString)
        if decision == .skip { return }
        loadSerial += 1
        let serial = loadSerial
        activeMaxPixel = maxPixel
        let key = gate.currentKey
            ?? ImageSourceKey(fileId: fileId,
                              urlString: urlString)
        if decision == .reload {
            image = nil
            failed = false
            if key.hasSource {
                DiagLog.shared.log(.info,
                    "IMG reload \(key.diagTag)")
            }
        }
        if let fid = fileId {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = library.attachmentData(fid)
                self.publish(
                    data: data,
                    failNote: "图片加载失败 fid=\(fid) "
                        + "bytes=\(data.count)",
                    serial: serial, key: key,
                    isReload: decision == .reload)
            }
        } else if let s = urlString, let url = URL(string: s) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                self.publish(
                    data: data,
                    failNote: "图片加载失败 url="
                        + "\(url.host ?? "?")",
                    serial: serial, key: key,
                    isReload: decision == .reload)
            }.resume()
        } else {
            failed = true
            // nil 源（占位块无图源）进程级首行留
            // 痕：旧形态此分支无行、本症在日志上
            // 无从判读（diag_image_card_load §2）。
            DiagLog.shared.logOnce(
                "img:nosource", .info,
                "IMG load nosource（占位块无图源）")
        }
    }

    /// 解码汇合点（P2-7 根治，定案 fix_svg_image_
    /// page.md）：fileId/URL 两路数据在此单点收
    /// 口——内容嗅探命中 SVG 走 SvgRasterizer 光
    /// 栅化异步路（ImageIO 对 SVG 无解码、恒失
    /// 败的死路在此改道），未命中走 MediaDecode
    /// 管线汇合（缓存/降采样/逐帧，审计批 3 收
    /// 口；旧 decodeImage 直调已整体退役）。发
    /// 布与失败行沿用既有形态，SVG 失败行加
    /// fmt=svg 标记与光栅图失败分开判读。
    private func publish(data: Data?, failNote: String,
                         serial: Int, key: ImageSourceKey,
                         isReload: Bool) {
        guard let data else {
            deliver(nil, isSvg: false, failNote: failNote,
                    serial: serial, key: key,
                    isReload: isReload)
            return
        }
        if isSvgData(data) {
            SvgRasterizer.shared.rasterize(data: data) {
                [weak self] img in
                self?.deliver(img, isSvg: true,
                              failNote: failNote,
                              serial: serial, key: key,
                              isReload: isReload)
            }
        } else {
            deliver(MediaDecode.image(
                        for: key, data: data,
                        maxPixel: activeMaxPixel),
                    isSvg: false,
                    failNote: failNote,
                    serial: serial, key: key,
                    isReload: isReload)
        }
    }

    private func deliver(_ img: UIImage?, isSvg: Bool,
                         failNote: String,
                         serial: Int, key: ImageSourceKey,
                         isReload: Bool) {
        let work = {
            // 代际守卫（主线程单点）：呈新键后旧
            // 键的在途结果（含 SVG 异步光栅路）到
            // 此已过期，直接弃、不覆新图不记行。
            guard serial == self.loadSerial else { return }
            self.image = img
            self.failed = img == nil
            if img != nil, isReload {
                DiagLog.shared.log(.info,
                    "IMG reload ok \(key.diagTag)")
            }
            // 加载失败结果侧记行（批 C）：附件缺
            // 失/坏图不再只有空白占位无痕。
            if img == nil {
                // 同文去重（G7/G8）：列表滚动可批
                // 量失败，改投 logErrorOnce 只留首
                // 行、不进徽章防冲掉真错误。
                DiagLog.shared.logErrorOnce(
                    failNote + (isSvg ? " fmt=svg" : ""))
            }
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }
}

/// 自检读面用图主色调（fix_image_card_load 两景
/// 的图身份判读）：1x1 绘制取平均色 hex——小图
/// 精确、大图近似，场景只用小夹具纯色图。
func imgToneHex(_ img: UIImage?) -> String {
    guard let img, let cg = img.cgImage else { return "" }
    var px: [UInt8] = [0, 0, 0, 0]
    let ctx = CGContext(
        data: &px, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo
            .premultipliedLast.rawValue)
    guard let ctx else { return "" }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1,
                            height: 1))
    return String(format: "%02x%02x%02x",
                  px[0], px[1], px[2])
}

/// 图片页缩放查看（用户 2026-11-26 裁定，破例于
/// 2024 定案的无手势口径）：UIScrollView 承载——初
/// 始按 contain 适配（小图不放大、上限 1:1），捏合
/// 缩放至适配倍率 ×4、双击在适配↔2.5 倍间切换、缩
/// 放后可平移，图小于视口时居中。动图由 UIImageView
/// 播 animatedImage（decodeImage 组装）。
struct ZoomableImageView: UIViewRepresentable {
    var image: UIImage
    var viewport: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.delegate = context.coordinator
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bouncesZoom = true
        let iv = UIImageView(image: image)
        iv.frame = CGRect(origin: .zero, size: image.size)
        sv.addSubview(iv)
        context.coordinator.imageView = iv
        context.coordinator.scrollView = sv
        let dbl = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        sv.addGestureRecognizer(dbl)
        return sv
    }

    func updateUIView(_ sv: UIScrollView,
                      context: Context) {
        let c = context.coordinator
        if c.imageView?.image !== image {
            c.imageView?.image = image
            c.imageView?.frame = CGRect(origin: .zero,
                                         size: image.size)
            sv.zoomScale = 0
        }
        c.fit(in: sv, viewport: viewport, imageSize: image.size)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        /// 上次 fit 的视口（L-5）：尺寸变化（旋转/
        /// 分栏）即触发倍率与偏移复位；不变时 fit 只
        /// 做下限抬回，不打扰用户缩放态。
        var lastViewport: CGSize = .zero

        func viewForZooming(in sv: UIScrollView) -> UIView? {
            imageView
        }

        func fit(in sv: UIScrollView, viewport: CGSize,
                 imageSize: CGSize) {
            guard viewport.width > 0, imageSize.width > 0
            else { return }
            let fitScale = min(viewport.width / imageSize.width,
                               viewport.height / imageSize.height)
            let base = min(fitScale, 1)
            sv.minimumZoomScale = base
            // 缩放上限 = 适配倍率 ×4、保底 1.0（批 K
            // F3 裁定保留）：超大图 base<0.25 时保底
            // 使 1:1 像素级查看恒可达，属增强；常规
            // 图与小图（base≥0.25）保底不触发、与 ×4
            // 口径逐值等价。verify [22] K22-2 锁此式。
            sv.maximumZoomScale = max(base * 4, 1)
            sv.contentSize = imageSize
            // 视口尺寸变化（旋转/分栏，审计 L-5）：
            // 旧倍率可大于新 base、旧平移在新视口无
            // 意义——倍率钳回 base、偏移归零居中。
            let resized = lastViewport != viewport
            lastViewport = viewport
            if resized {
                sv.zoomScale = base
            } else if sv.zoomScale < base
                        || sv.zoomScale == 0 {
                sv.zoomScale = base
            }
            center(in: sv, viewport: viewport)
            if resized {
                sv.contentOffset = CGPoint(
                    x: -sv.contentInset.left,
                    y: -sv.contentInset.top)
            }
        }

        func scrollViewDidZoom(_ sv: UIScrollView) {
            center(in: sv, viewport: sv.bounds.size)
        }

        /// 图（缩放后）小于视口时以 contentInset 居中。
        func center(in sv: UIScrollView, viewport: CGSize) {
            guard let iv = imageView else { return }
            let c = iv.frame.size
            let x = max((viewport.width - c.width) / 2, 0)
            let y = max((viewport.height - c.height) / 2, 0)
            sv.contentInset = UIEdgeInsets(
                top: y, left: x, bottom: y, right: x)
        }

        @objc func doubleTap(_ r: UITapGestureRecognizer) {
            guard let sv = scrollView, let iv = imageView
            else { return }
            if sv.zoomScale > sv.minimumZoomScale + 0.01 {
                sv.setZoomScale(sv.minimumZoomScale,
                                animated: true)
            } else {
                let p = r.location(in: iv)
                let target = min(sv.minimumZoomScale * 2.5,
                                 sv.maximumZoomScale)
                let w = sv.bounds.width / target
                let h = sv.bounds.height / target
                sv.zoom(to: CGRect(x: p.x - w / 2,
                                   y: p.y - h / 2,
                                   width: w, height: h),
                        animated: true)
            }
        }
    }
}

struct ItemImageView: View {
    let fileId: String?
    let urlString: String?
    var library: Library
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                // 动图承载（AUD-D-01）：fill 语义
                // 由 AnimImageView 复刻，GIF 逐帧
                // 由 UIImageView 驱动。
                AnimImageView(image: img,
                              mode: .scaleAspectFill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: loader.failed
                            ? "photo.badge.exclamationmark"
                            : "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .clipped()
        .onAppear {
            loader.load(fileId: fileId, urlString: urlString,
                        library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        // 源键变化重呈 loader（fix_image_card_
        // load）：gallery 换图/删项移位后瓦随项走
        // 靠此钩 + 闸门键控，旧图不再按位留守。
        .onChange(of: fileId) { _ in
            loader.load(fileId: fileId,
                        urlString: urlString,
                        library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .onChange(of: urlString) { _ in
            loader.load(fileId: fileId,
                        urlString: urlString,
                        library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .background(UITestAnchor(providesFrame: false) {
            UITestSurfaceEntry(
                id: "image.item", kind: "image",
                instance: fileId ?? urlString ?? "none",
                state: [
                    "fid": { fileId ?? "" },
                    "url": { urlString ?? "" },
                    "hasImage": {
                        loader.image != nil
                            ? "true" : "false"
                    },
                    "failed": {
                        loader.failed ? "true" : "false"
                    },
                    "tone": { imgToneHex(loader.image) },
                ])
        })
    }
}

struct ImageBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    /// 拾起态（图本体即视觉面，框挂图上、半径 22）。
    var lifted: Bool = false
    @StateObject private var loader = ImageLoader()
    // 语义字体喂点（fix_dynamic_type_follow：
    // relativeTo = 被替样式本身、与 UIFontMetrics
    // 同表；下同各视图）。
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15

    var body: some View {
        Group {
            if block.fileId == nil && block.imageURL == nil {
                // 空图占位面（Web .atomic-placeholder
                // 口径：玻璃面 + padding 24 + radius
                // 32）——旧实现只是无面文案行、拾起框
                // 只能挂行盒借位；现面在子视图内、框
                // 随面派生（fix_lift_spacing.md）。
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                    Text(Lang.t("media.add_image"))
                        .font(.system(size: f15))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
                .glassCard(radius: Radius.cardL)
                .background {
                    if lifted {
                        LiftFrame(faceRadius: Radius.cardL)
                    }
                }
            } else if let img = loader.image {
                // Web 口径（线 1 #31/#32）：圆角 22、
                // 自然宽居中、不放大（宽上限=自然宽）、
                // 限高 668 内 contain。承载换 Anim-
                // ImageView（AUD-D-01）：fit 尺寸协
                // 商由其 sizeThatFits 复刻上列口径、
                // GIF 逐帧由 UIImageView 驱动。
                // 命中形（fix_image_tap_regression）：
                // 承载恒被动（isUserInteractionEnabled
                // = false）不提供命中体，行级点按手势
                // 的命中域须由本链显式声明——批 3 换
                // 承载前由 SwiftUI Image 叶子天然提
                // 供，换后缺此行图面点按恒不达（真机
                // 实证）；与图文行面同式收口于此。
                AnimImageView(image: img,
                              mode: .scaleAspectFit,
                              fitMaxHeight: 668)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.cardS))
                    .contentShape(Rectangle())
                    .background {
                        if lifted {
                            LiftFrame(faceRadius: Radius.cardS)
                        }
                    }
                    .frame(maxWidth: .infinity)
            } else if loader.failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text(Lang.t("media.image_unavailable"))
                        .font(.system(size: f15))
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .onAppear {
            loader.load(block: block, library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        // 源键变化重呈 loader（fix_image_card_
        // load）：斜杠空块后 replaceImage 原位塞
        // fid、已有图块换图——块视图不重建，靠此
        // 钩 + 闸门键控当场重载，不再恒失败/恒旧图。
        .onChange(of: block.fileId) { _ in
            loader.load(block: block, library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .onChange(of: block.imageURL) { _ in
            loader.load(block: block, library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .background(UITestAnchor(providesFrame: false) {
            UITestSurfaceEntry(
                id: "image.block", kind: "image",
                instance: block.id,
                state: [
                    "fid": { block.fileId ?? "" },
                    "url": { block.imageURL ?? "" },
                    "hasImage": {
                        loader.image != nil
                            ? "true" : "false"
                    },
                    "failed": {
                        loader.failed ? "true" : "false"
                    },
                    "tone": { imgToneHex(loader.image) },
                ])
        })
    }
}

// PHPicker（UIKit 口径；SwiftUI 的 PhotosPicker 在本
// 工具链的 27.2 SwiftUI 模块里不可见）。
/// 选图器给出的真实文件名：suggestedName 优先；无
/// 扩展名时按内容类型补扩展（IMG_1234 → IMG_1234.
/// jpeg）。图片页标题的查名来源在此登记进清单。
func pickerFileName(_ provider: NSItemProvider) -> String {
    var name = provider.suggestedName ?? ""
    if !name.contains(".") {
        let ext = provider.registeredTypeIdentifiers
            .first.flatMap {
                UTType($0)?.preferredFilenameExtension
            }
        if let ext, !ext.isEmpty {
            name = name.isEmpty ? "photo.\(ext)"
                : "\(name).\(ext)"
        }
    }
    return name
}

struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: (Data, String) -> Void
    /// 视频通道（F-15）：默认关——头像/换图/图库换
    /// 图等既有调用点只收图、行为不变；仅「添加附
    /// 件 · 图片/视频」一路开启，选中视频时经文件
    /// 表示读字节走 onPickVideo（成 video 块）。
    var allowVideo = false
    var onPickVideo: ((Data, String) -> Void)? = nil

    func makeUIViewController(
        context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = allowVideo
            ? .any(of: [.images, .videos]) : .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(
        _ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject,
        PHPickerViewControllerDelegate {
        var parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider
            else { return }
            let name = pickerFileName(provider)
            // 视频支（F-15）：loadFileRepresentation 给
            // 临时文件 URL，回调内即读成 Data（URL 在
            // 回调返回后即被系统回收）。
            if let onPickVideo = parent.onPickVideo,
               provider.hasItemConformingToTypeIdentifier(
                UTType.movie.identifier) {
                provider.loadFileRepresentation(
                    forTypeIdentifier: UTType.movie.identifier
                ) { url, _ in
                    guard let url,
                          let data = try? Data(
                            contentsOf: url) else { return }
                    DispatchQueue.main.async {
                        onPickVideo(data, name)
                    }
                }
                return
            }
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, _ in
                if let data {
                    DispatchQueue.main.async {
                        self.parent.onPick(data, name)
                    }
                }
            }
        }
    }
}

/// 多选选图（图库编辑态追加用）：回调按选择序逐张
/// 给数据，全部到齐后一次性回主线程。
struct MultiPhotoPicker: UIViewControllerRepresentable {
    var onPick: ([(Data, String)]) -> Void

    func makeUIViewController(
        context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(
        _ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject,
        PHPickerViewControllerDelegate {
        var parent: MultiPhotoPicker
        init(_ p: MultiPhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }
            var datas: [(Data, String)?] =
                Array(repeating: nil, count: results.count)
            let group = DispatchGroup()
            for (i, r) in results.enumerated() {
                group.enter()
                let name = pickerFileName(r.itemProvider)
                r.itemProvider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    if let data { datas[i] = (data, name) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.parent.onPick(datas.compactMap { $0 })
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    /// 分享结局回调（completed / error）：附件打开
    /// 路径传之记 ATT 结局行（Web open_js_file 同
    /// 口径，批 K F4）；备份导出面传之锚 toast 于
    /// 分享完成（BK-3）；其余调用点不传、行为不变。
    var onComplete: ((Bool, Error?) -> Void)? = nil
    func makeUIViewController(
        context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil)
        if let onComplete {
            vc.completionWithItemsHandler = {
                _, completed, _, error in
                onComplete(completed, error)
            }
        }
        return vc
    }
    func updateUIViewController(
        _ vc: UIActivityViewController, context: Context) {}
}

// ── 时间格式化（I3：日期词走语言包、formatter 的
// locale 随 app 内语言——立项 §3 裁定，否则语言切
// 英文而日期仍按系统出中文词，自相矛盾） ──────────
enum Fmt {
    static var locale: Locale {
        Locale(identifier: LangStore.shared.code)
    }

    static func timeOfDay(_ d: Date) -> String {
        let tmpl = DateFormatter.dateFormat(
            fromTemplate: "j", options: 0,
            locale: locale) ?? ""
        let f = DateFormatter()
        f.locale = locale
        if tmpl.contains("a") {
            let h = Calendar.current.component(.hour, from: d)
            let ap = Lang.t(h < 12 ? "time.am" : "time.pm")
                .replacingOccurrences(of: "'", with: "''")
            f.dateFormat = "'\(ap)' h:mm"
        } else {
            f.dateFormat = "HH:mm"
        }
        return f.string(from: d)
    }

    /// 备份时刻文案：今天/昨天 + 时刻，或 M/D + 时刻。
    static func backupWhen(_ ts: Double) -> String {
        // 从未备份（V7，backup.never）：hero 拼出
        // 「上次备份 暂无」；设置行未备份文案走
        // freshnessMain 的独立分支，不经此处。
        if ts <= 0 { return Lang.t("backup.never") }
        let d = Date(timeIntervalSince1970: ts)
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return "\(Lang.t("group.today")) \(timeOfDay(d))"
        }
        if cal.isDateInYesterday(d) {
            return "\(Lang.t("group.yesterday")) \(timeOfDay(d))"
        }
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "M/d"
        return "\(f.string(from: d)) \(timeOfDay(d))"
    }

    static func fullStamp(_ ts: Double) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }
}

// ── 诊断日志管线（Web 口径：2000 行环 + 落盘持久 +
// 按天冻结归档上限 60 + 等级只过滤呈现不滤导出） ────
enum DiagLevel: String {
    case info, warn, error
}

struct DiagEntry: Codable {
    var ts: Double
    var level: String
    var text: String

    var dayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    var line: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let t = f.string(from: Date(timeIntervalSince1970: ts))
        switch level {
        case "warn": return "[\(t) W] \(text)"
        case "error": return "[\(t) E] \(text)"
        default: return "[\(t)] \(text)"
        }
    }
}

struct DiagArchive: Codable, Identifiable {
    var stamp: String  // 归档标 "YYYY-MM-DD HH:mm"
    var entries: [DiagEntry]
    var id: String { stamp }
    var lines: [String] { entries.map { $0.line } }
}

/// 错误徽章（Web errbadge 移植，用户 2026-11-26 裁
/// 定）：编辑页失败的常驻可见通道——内存数组上限
/// 20、不落盘、应用重启即清（Web 同口径）；每次投
/// 递以 Diag ERRBADGE 行记结果侧总量。kind: ERROR
/// 红底优先呈现，WARN 黄底。
final class ErrBadge: ObservableObject {
    static let shared = ErrBadge()
    struct Entry: Identifiable {
        let id = UUID()
        var kind: String  // "ERROR" / "WARN"
        var message: String
        /// 位置（Web loc：仅全局错误来源有；原生无
        /// 全局错误钩、恒空，面板非空才显——批 K F5）。
        var loc: String
        /// 底层错误文本（Web stack 的平台等价物）：
        /// 投递点手握 error 时传入，面板以堆栈块呈
        /// 现；无则空、面板不显（批 K F5）。
        var detail: String
        var time: String
    }
    @Published var entries: [Entry] = []
    @Published var panelOpen = false
    var hasError: Bool {
        entries.contains { $0.kind == "ERROR" }
    }
    /// 条目时间（Web toLocaleString 同口径：完整
    /// locale 日期时间串、随 app 内语言；批 K F5，
    /// 此前仅 HH:mm:ss）。
    private static var stamp: String {
        let f = DateFormatter()
        f.locale = Fmt.locale
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: Date())
    }
    func addError(_ message: String,
                  detail: String? = nil) {
        add(kind: "ERROR", message: message,
            detail: detail)
    }
    func addWarn(_ message: String,
                 detail: String? = nil) {
        add(kind: "WARN", message: message,
            detail: detail)
    }
    private func add(kind: String, message: String,
                     detail: String?) {
        // detail 行数上限（Web 口径：add_warn 取
        // 前 4 行、全局 add_error 前 8 行；原生
        // ERROR 为操作失败投递、按 8 行收）。
        let cap = kind == "WARN" ? 4 : 8
        let det = (detail ?? "")
            .split(separator: "\n",
                   omittingEmptySubsequences: false)
            .prefix(cap)
            .joined(separator: "\n")
        entries.append(Entry(
            kind: kind, message: message, loc: "",
            detail: det, time: Self.stamp))
        if entries.count > 20 {
            entries.removeFirst(entries.count - 20)
        }
        DiagLog.shared.log(.info,
            "ERRBADGE add \(kind) total=\(entries.count)")
    }
    func clear() {
        let n = entries.count
        entries.removeAll()
        panelOpen = false
        DiagLog.shared.log(.info, "ERRBADGE clear \(n)")
    }
}

/// 错误徽章呈现层（G8 上提）：原挂 EditorView 仅编辑
/// 页可见，现抽为独立视图挂应用根 ZStack——对位 Web
/// 徽章挂 App 根，首页/编辑页/设置族之上全可见（系
/// 统 sheet 盖其上，与 Web 模态层级口径可接受）。
/// 定位口径原样：右下 right 16、bottom = safe + 64、
/// 36×36 radius 18、ERROR 红底/仅 WARN 黄底、「!」
/// 12/700 + 计数 10/600；面板宽 min(320, 屏宽-32)、
/// 内容上限 280，头行标题 + 清除钮、条目倒序。
struct ErrBadgeOverlay: View {
    @ObservedObject private var badge = ErrBadge.shared
    @EnvironmentObject private var langStore: LangStore
    // 文字大小跟随系统（Dynamic Type 全量实装）：
    // 无语义等值的字号走 ScaledMetric。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2)
    private var f10: CGFloat = 10
    @ScaledMetric(relativeTo: .caption2)
    private var f9: CGFloat = 9
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 8) {
                    if badge.panelOpen
                        && !badge.entries.isEmpty {
                        // 面板宽固定 320（Web .eb-panel
                        // 口径，J2-F28；不再随屏宽收缩）。
                        panel
                            .frame(width: 320)
                            .transition(.opacity)
                    }
                    if !badge.entries.isEmpty {
                        Button {
                            badge.panelOpen.toggle()
                            if badge.panelOpen {
                                DiagLog.shared.log(.info,
                                    "ERRBADGE panel open "
                                    + "total=\(badge.entries.count)")
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text("!")
                                    .font(.system(size: f12, weight: .bold))
                                Text(badge.entries.count > 99
                                    ? "99+"
                                    : "\(badge.entries.count)")
                                    .font(.system(
                                        size: f10,
                                        weight: .semibold))
                            }
                            .foregroundStyle(T.onAccent)
                            // 韧性（impl_dt_layout_resilience）：
                            // 计数文案随字号缩放，定尺寸 36 圆
                            // 在大字号下文案溢出圆面——改最小
                            // 尺寸 + 横内距的胶囊形态，默认档
                            // 逐值不变（内容宽 + 内距 ≤ 36 时
                            // 恒 36×36、Capsule 即原 18 圆角）。
                            .padding(.horizontal, 7)
                            .frame(minWidth: 36, minHeight: 36)
                            .background(
                                badge.hasError
                                    ? T.dangerBright
                                    : T.warning,
                                in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom,
                         geo.safeAreaInsets.bottom + 64)
                .animation(.easeInOut(duration: 0.2),
                           value: badge.entries.count)
                .animation(.easeInOut(duration: 0.2),
                           value: badge.panelOpen)
            }
        }
        .allowsHitTesting(!badge.entries.isEmpty)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(badge.hasError
                     ? Lang.t("errbadge.title_error")
                     : Lang.t("errbadge.title_warn"))
                    .font(.system(size: f13, weight: .bold))
                    // ERROR 标题色 = --color-danger-
                    // light（J2-F29）；徽章底与条目图标
                    // 仍用 dangerBright，不随此改。
                    .foregroundStyle(badge.hasError
                        ? T.dangerLight : T.warning)
                Spacer()
                Button(Lang.t("errbadge.clear")) {
                    badge.clear()
                }
                    .font(.system(size: f11))
                    .foregroundStyle(T.textSecondary)
                    // 清除钮命中形（Web .eb-clear 口
                    // 径，J2-F30）：padding 2/6、radius
                    // 6、透明底。
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(RoundedRectangle(
                        cornerRadius: 6))
            }
            .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(
                        Array(badge.entries.reversed())
                    ) { e in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName:
                                e.kind == "ERROR"
                                    ? "xmark.octagon.fill"
                                    : "exclamationmark.triangle.fill")
                                .font(.system(size: f14))
                                .foregroundStyle(
                                    e.kind == "ERROR"
                                        ? T.dangerBright
                                        : T.warning)
                            VStack(alignment: .leading,
                                   spacing: 3) {
                                // 消息截 120 字（Web
                                // eb-entry-msg 同口径）。
                                Text(String(
                                    e.message.prefix(120)))
                                    .font(.system(size: f12, weight: .semibold))
                                    .foregroundStyle(
                                        T.textMain)
                                // meta 行（Web eb-
                                // entry-meta）：loc 非
                                // 空才显 + 完整时间串。
                                HStack(spacing: 8) {
                                    if !e.loc.isEmpty {
                                        Text(e.loc)
                                    }
                                    Text(e.time)
                                }
                                .font(.system(size: f10))
                                .foregroundStyle(
                                    T.textSecondary)
                                // 堆栈块（Web eb-entry-
                                // stack：9 号等宽、次级
                                // 色、行高 1.4；批 K F5）。
                                if !e.detail.isEmpty {
                                    Text(e.detail)
                                        .font(.system(
                                            size: f9,
                                            design: .monospaced))
                                        .foregroundStyle(
                                            T.textSecondary)
                                        .lineSpacing(f9 * 0.4)
                                        .padding(.top, 1)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(T.borderSoft)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            // 滚动区弹性占余高（J2-F28）：面板本体限
            // 高 360、整体内滚，不再写死 280。
        }
        .padding(14)
        .frame(maxHeight: 360)
        .overlayCard(radius: Radius.panelS)
    }
}

final class DiagLog: ObservableObject {
    static let shared = DiagLog()

    /// 归档戳格式化（DiagLog 专用，固定 POSIX 口径）。
    /// 红线：DiagLog 必须零依赖（叶子）——不得引用
    /// Fmt/LangStore/Lang。0.9.43 真机点开闪退定因
    /// （.ips 2026-11-27）：LangStore.init 末行记
    /// Diag → loadIfNeeded 冻结旧日归档时经
    /// Fmt.fullStamp → Fmt.locale 回读尚在 init 中的
    /// LangStore.shared，dispatch_once 递归锁 SIGTRAP。
    /// 触发条件 = 诊断存量含往日条目（覆盖安装跨天）。
    /// verify [12] 断言本类体内无 Fmt./Lang. 引用。
    static func diagStamp(_ ts: Double) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date(timeIntervalSince1970: ts))
    }

    @Published var today: [DiagEntry] = []
    @Published var archives: [DiagArchive] = []
    private var loaded = false

    /// diag 隔离域目录（哨兵文件与热更新指令缓存同
    /// 域共用此真源：库坏时此域仍可读写）。纯路径计
    /// 算 + 建目录，不依赖任何其他单例（叶子纪律）。
    static func diagDirPath() -> String {
        let d = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask)[0]
            .appendingPathComponent("diag").path
        try? FileManager.default.createDirectory(
            atPath: d, withIntermediateDirectories: true)
        return d
    }

    private var dir: String { Self.diagDirPath() }
    private var todayPath: String { dir + "/today.json" }
    private var archivePath: String { dir + "/archives.json" }

    private func read<T: Decodable>(_ path: String) -> T? {
        guard let data = try? Data(
                contentsOf: URL(fileURLWithPath: path))
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to path: String) {
        if let data = try? JSONEncoder().encode(value) {
            // 原子写（AUD-E-03）：.atomic = 同目录临
            // 时文件 + rename 替换，崩在写盘中旧文
            // 件完好（Diag 原为全家唯一非原子落盘
            // 面，哨兵/ops 缓存均已 .atomic）。
            try? data.write(to: URL(fileURLWithPath: path),
                            options: .atomic)
        }
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let stored: [DiagEntry] = read(todayPath) ?? []
        let archs: [DiagArchive] = read(archivePath) ?? []
        archives = archs
        let todayKey = DiagEntry(
            ts: Date().timeIntervalSince1970, level: "info",
            text: "").dayKey
        let old = stored.filter { $0.dayKey != todayKey }
        today = stored.filter { $0.dayKey == todayKey }
        if !old.isEmpty {
            // 按天冻结（新→旧），插到既有归档之前。归
            // 档戳 = 日志当天（组内最后一条的时刻），
            // 不用冻结时刻冒充（批 C 口径修正）。
            let days = Dictionary(grouping: old) { $0.dayKey }
            let fresh = days.keys.sorted(by: >).map { day in
                let entries = (days[day] ?? [])
                    .sorted { $0.ts < $1.ts }
                return DiagArchive(
                    stamp: Self.diagStamp(
                        entries.last?.ts
                            ?? Date().timeIntervalSince1970),
                    entries: entries)
            }
            // 截断留痕（G10）：超 60 丢弃须记量。此处
            // 记行会回入 appendEntry，其内 loadIfNeeded
            // 因 loaded 已置 true 直接返回，不递归。
            let merged = fresh + archives
            if merged.count > 60 {
                DiagLog.shared.log(.warn,
                    "DIAG archives truncated "
                    + "dropped=\(merged.count - 60) keep=60")
            }
            archives = Array(merged.prefix(60))
        }
        applyAutodelete()
        // S9 延后：冻结/自动删除的数据结构变更在加载
        // 时完成，但合并写盘不再同步直写（冷启写放大
        // 且与开库抢 IO）——置脏标走延后 flush（2s 定
        // 时或 didLoad 后 Library 主动调用）。未及
        // flush 即崩溃时磁盘仍是旧结构，下次加载重演
        // 冻结/删除（派生自存量数据，幂等无损）。
        structuralDirty = true
        scheduleStructuralFlush()
    }

    /// 结构性写盘延后（S9）：loadIfNeeded 的冻结合
    /// 并与 autodel 落盘统一经此出口。S13 guard 点：
    /// 指令点名 OpsStep.diagFreezePersist 时跳过本段
    /// 写盘并留痕。
    /// R3 真隔离（取代 R1 取舍）：落盘拆为分文件出
    /// 口——archives.json 只经本结构 flush 写、
    /// today.json 由记行节流写；结构脏未清期间记行
    /// 写一律并入结构 flush（双文件同写保持一致快
    /// 照，磁盘永不出现「today 已冻结、archives 未
    /// 冻结」的半态）。guard 跳过时脏标不清、两文
    /// 件都不再写：指令的停写真正生效，救援路径的
    /// Diag 写盘不可能绕过 guard 反噬启动；内存结
    /// 构不变，下次启动从磁盘存量重演冻结/删除
    /// （幂等无损）。
    private var structuralDirty = false
    private var structuralWork: DispatchWorkItem?
    private func scheduleStructuralFlush() {
        guard structuralWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.structuralWork = nil
            self?.flushStructuralPersist()
        }
        structuralWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2, execute: work)
    }

    func flushStructuralPersist() {
        guard structuralDirty else { return }
        structuralWork?.cancel()
        structuralWork = nil
        // guard 判定在清脏之前（R3 真隔离）：被指
        // 令跳过时脏标保留，记行写继续并入本出口
        // 等待——不得像 R1 那样清脏后任由记行写把
        // 结构变更顺带写出。
        if OpsDirectives.cached().isDisabled(
            OpsStep.diagFreezePersist) {
            logOnce("ops-skip-diagfreeze", .info,
                    "OPS skip step="
                    + OpsStep.diagFreezePersist)
            return
        }
        structuralDirty = false
        persist()
    }

    /// 双文件同写（结构出口专用）：today 与
    /// archives 一起落盘，磁盘恒为一致快照。
    private func persist() {
        write(today, to: todayPath)
        write(archives, to: archivePath)
    }

    /// 记行出口：只写 today.json。archives 的唯一
    /// 写出口是结构 flush（guard 辖区）——这是 R3
    /// 真隔离的落点。
    private func persistToday() {
        write(today, to: todayPath)
    }

    /// 落盘节流（批 C，对 Web 1s 节流合并写口径）：
    /// 普通行 1s 内合并一写，error 行立即刷盘；结构
    /// 脏未清时不单独写 today（防半态落盘），并入
    /// 结构 flush：普通行催 2s 定时、error 行立即
    /// 催（guard 拦下时不写、脏标保留）。
    private var persistWork: DispatchWorkItem?
    private func schedulePersist(immediate: Bool) {
        if structuralDirty {
            if immediate {
                flushStructuralPersist()
            } else {
                scheduleStructuralFlush()
            }
            return
        }
        if immediate {
            persistWork?.cancel()
            persistWork = nil
            persistToday()
            return
        }
        guard persistWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.persistWork = nil
            self?.persistToday()
        }
        persistWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 1, execute: work)
    }

    private func freezeToday() {
        guard !today.isEmpty else { return }
        // 戳 = 被冻结那天最后一条的时刻（日志当天）。
        let stamp = Self.diagStamp(
            today.map(\.ts).max()
                ?? Date().timeIntervalSince1970)
        archives.insert(
            DiagArchive(stamp: stamp, entries: today), at: 0)
        if archives.count > 60 {
            DiagLog.shared.log(.warn,
                "DIAG archives truncated "
                + "dropped=\(archives.count - 60) keep=60")
        }
        archives = Array(archives.prefix(60))
        today = []
        // 冻结是结构变更（R3）：置脏并催结构 flush，
        // 在它落盘前记行写并入等待（见 schedulePersist）。
        structuralDirty = true
        scheduleStructuralFlush()
    }

    /// 自动删除（Web 口径）：开启后日志超 30 天自动删除。
    func applyAutodelete() {
        guard UserDefaults.standard.bool(
            forKey: "diagAutodel") else { return }
        let cutoff = Date().timeIntervalSince1970
            - 30 * 86400
        // 删除量留痕（G10）：删了多少此前静默。
        let archBefore = archives.count
        let todayBefore = today.count
        archives.removeAll { arch in
            (arch.entries.last?.ts ?? 0) < cutoff
        }
        today.removeAll { $0.ts < cutoff }
        let da = archBefore - archives.count
        let dt = todayBefore - today.count
        if da > 0 || dt > 0 {
            DiagLog.shared.log(.info,
                "DIAG autodel removed archives=\(da) "
                + "entries=\(dt)")
            // 结构变更置脏（R3）：与加载期同口径经
            // 结构 flush 落盘（设置页开关触发亦然）。
            structuralDirty = true
            scheduleStructuralFlush()
        }
    }

    func log(_ level: DiagLevel, _ text: String) {
        let entry = DiagEntry(
            ts: Date().timeIntervalSince1970,
            level: level.rawValue, text: text)
        let work = { [weak self] in
            guard let self else { return }
            self.appendEntry(entry)
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }

    /// 入环主体（log 与 once 原语共用，防节流/冻结
    /// 逻辑两份分叉）。调用方须在主队列上。
    private func appendEntry(_ entry: DiagEntry) {
        loadIfNeeded()
        if let first = today.first,
           first.dayKey != entry.dayKey {
            freezeToday()
        }
        today.append(entry)
        // 当天环上限 2000（2026-11-28 用户裁定由 300
        // 扩容，Web diag.rs CAP 为源口径、双端同值由
        // verify [12] J12-2 与 verify_rustweb §20 双锁；
        // 定案 diag_reachback_attribution.md）。
        if today.count > 2000 {
            today.removeFirst(today.count - 2000)
        }
        schedulePersist(
            immediate: entry.level == DiagLevel.error.rawValue)
    }

    /// 去重打点原语（Web diag.rs log_once/log_err 口
    /// 径，G7）：进程级 seen 集（不落盘、随进程重启
    /// 清空），同 key 只记首行。判定与入环在同一主
    /// 队列工作闭包内，天然无竞态。key 纪律：必须是
    /// 模板串（可含有界标识如 id/查询词），禁止拼整
    /// 段用户正文。
    private var onceKeys: Set<String> = []

    func logOnce(_ key: String, _ level: DiagLevel,
                 _ text: String) {
        let entry = DiagEntry(
            ts: Date().timeIntervalSince1970,
            level: level.rawValue, text: text)
        let work = { [weak self] in
            guard let self else { return }
            guard self.onceKeys.insert(key).inserted
            else { return }
            self.appendEntry(entry)
        }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.async(execute: work) }
    }

    /// 同文错误去重（Web log_err 口径）：key =
    /// "err:" + 全文，供图片加载失败等可刷屏的同文
    /// 错误改投，首行留痕、后续同文静默。
    func logErrorOnce(_ text: String) {
        logOnce("err:" + text, .error, text)
    }
}

/// 日志呈现过滤（只影响本页与视窗页，导出全量）。
/// G1 门槛制（Web 口径）：All/Info 全显、Warn 显
/// warn+error、Error 只显 error——原先精确匹配在
/// 选「警告」时藏掉全部 error 行，与排障直觉相反。
func diagFiltered(_ entries: [DiagEntry],
                  level: String) -> [DiagEntry] {
    func rank(_ l: String) -> Int {
        switch l {
        case "error": return 2
        case "warn": return 1
        default: return 0
        }
    }
    let minRank: Int
    switch level {
    case "warn": minRank = 1
    case "error": minRank = 2
    default: minRank = 0
    }
    return entries.filter { rank($0.level) >= minRank }
}

/// 横向流式 wrap 布局（F8 历史归档胶囊）：子视图
/// 左起逐个排、超宽换行，行距/间距同 spacing。
/// Layout 协议部署目标 16.0 可用。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        let w = maxWidth == .infinity ? x : maxWidth
        return CGSize(width: w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

// ── 语言（原生 i18n 路线 c 的应用内部分，立项见
// docs/reports/plan_native_i18n.md）：真源 = Web 语
// 言包 rust/apps/web/lang/*.json，构建时原样拷入
// bundle 的 lang/ 目录、五语全内置；查表回退链与
// Web 逐字一致（当前包 → zh-CN → 键名），占位符沿
// 用 {name} 语法（Web tf 同义）。用户内容（备忘标
// 题/正文/标签、附件名、备份内容）永不走语言包，
// 语言包只覆盖 UI 壳；Diag 日志行不本地化（证据
// 可对读性，立项 §3），仅本类 LANG 打点随语言走。
final class LangStore: ObservableObject {
    static let shared = LangStore()
    static let codes = ["zh-CN", "zh-TW", "en-US",
                        "ja-JP", "ko-KR"]
    /// 偏好键：值 "system" = 跟随系统、语言码 = 手
    /// 动选定；缺省 = 从未裁定（见 init 判据）。
    private static let kPref = "langPref"

    /// 当前生效语言码（手动选定或解析结果）。
    @Published private(set) var code: String
    /// 三态之「跟随系统」在位（手动五语时 false）。
    @Published private(set) var followSystem: Bool
    private var pack: [String: String]
    private let base: [String: String]
    /// 系统 locale 变更监听句柄（T-4）：init 注册、
    /// 随单例存活，不手动注销。
    private var localeObserver: NSObjectProtocol?

    init() {
        let basePack = Self.loadPack("zh-CN")
        base = basePack
        let d = UserDefaults.standard
        var resolved = "zh-CN"
        var follow = false
        if let pref = d.string(forKey: Self.kPref) {
            if pref == "system" {
                follow = true
                resolved = Self.systemCode()
            } else if Self.codes.contains(pref) {
                resolved = pref
            }
        } else if Self.hasExistingState() {
            // 存量用户（用户裁定 2026-11-26）：无偏
            // 好按 zh-CN 解析、零突变；裁定结果落盘，
            // 判据只跑一次（否则全新装第二启会被自家
            // 已建的库误判为存量）。
            d.set("zh-CN", forKey: Self.kPref)
        } else {
            // 全新安装（同裁定）：默认跟随系统，裁定
            // 同样落盘为 "system"。
            follow = true
            resolved = Self.systemCode()
            d.set("system", forKey: Self.kPref)
        }
        followSystem = follow
        code = resolved
        pack = resolved == "zh-CN"
            ? basePack : Self.loadPack(resolved)
        DiagLog.shared.log(.info, "LANG init \(resolved)")
        // T-4：跟随系统时运行中改系统语言即时重解
        // 析——监听 locale 变更，回调仅 followSystem
        // 在位时沿 applyFollowSystem 单点重解析（既
        // 有 LANG follow-system 打点随之落行）；手动
        // 模式零动作。
        localeObserver = NotificationCenter.default
            .addObserver(
                forName: NSLocale
                    .currentLocaleDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.followSystem
                    else { return }
                    self.applyFollowSystem()
                }
    }

    /// 点选具体语言（语言页 E4）：写偏好 + 即时换
    /// 包，全界面经观察本 store 反应式重渲染。
    func apply(_ newCode: String) {
        guard Self.codes.contains(newCode) else { return }
        UserDefaults.standard.set(newCode,
                                  forKey: Self.kPref)
        followSystem = false
        code = newCode
        pack = newCode == "zh-CN" ? base
            : Self.loadPack(newCode)
        DiagLog.shared.log(.info,
            "LANG applied \(newCode)")
    }

    /// 点选「跟随系统」：写偏好 + 按系统语言解析。
    func applyFollowSystem() {
        UserDefaults.standard.set("system",
                                  forKey: Self.kPref)
        followSystem = true
        let resolved = Self.systemCode()
        code = resolved
        pack = resolved == "zh-CN" ? base
            : Self.loadPack(resolved)
        DiagLog.shared.log(.info,
            "LANG follow-system -> \(resolved)")
    }

    /// 查表（回退链：当前包 → zh-CN → 键名本身）。
    func lookup(_ key: String) -> String {
        pack[key] ?? base[key] ?? key
    }

    /// 带 {name} 占位符的查表（Web tf 同语义）。
    func lookupf(_ key: String,
                 _ args: [String: String]) -> String {
        var s = lookup(key)
        for (k, v) in args {
            s = s.replacingOccurrences(
                of: "{" + k + "}", with: v)
        }
        return s
    }

    /// 系统语言 → 五语映射（立项 §3 映射表）：zh 按
    /// script/地区分简繁，en/ja/ko 直映，其余回退
    /// zh-CN（与 Web 默认底一致）。
    static func systemCode() -> String {
        let id = Locale.preferredLanguages.first
            ?? "zh-Hans"
        if id.hasPrefix("zh") {
            if id.contains("Hant") || id.contains("TW")
                || id.contains("HK")
                || id.contains("MO") {
                return "zh-TW"
            }
            return "zh-CN"
        }
        if id.hasPrefix("en") { return "en-US" }
        if id.hasPrefix("ja") { return "ja-JP" }
        if id.hasPrefix("ko") { return "ko-KR" }
        return "zh-CN"
    }

    /// 存量状态判据（用户裁定）：库文件已存在，或
    /// 既有偏好键任一在位。路径与 Library.storeDir
    /// 同构但不经其访问——storeDir 访问会顺手建目
    /// 录，且本判定须赶在 Library.load 开库之前。
    private static func hasExistingState() -> Bool {
        let fm = FileManager.default
        if let sup = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first {
            let db = sup.appendingPathComponent(
                "library/moment.db").path
            if fm.fileExists(atPath: db) { return true }
        }
        let d = UserDefaults.standard
        let sentinels = ["launchInProgress", "launchStep",
                         "lastExportTs", "lastEditTs",
                         "diagAutodel", "diagLevel"]
        return sentinels.contains {
            d.object(forKey: $0) != nil
        }
    }

    private static func loadPack(
        _ code: String) -> [String: String] {
        guard let url = Bundle.main.url(
                forResource: code,
                withExtension: "json",
                subdirectory: "lang"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization
                .jsonObject(with: data)
                as? [String: String]
        else { return [:] }
        return obj
    }

    /// 语言本名（语言页行名与设置行 meta 用；本名
    /// 不随界面语言变化）。
    static func nativeName(_ code: String) -> String {
        switch code {
        case "zh-TW": return "繁體中文"
        case "en-US": return "English"
        case "ja-JP": return "日本語"
        case "ko-KR": return "한국어"
        default: return "简体中文"
        }
    }

    /// 英文名（语言页副文案，Web 行形态同款）。
    static func englishName(_ code: String) -> String {
        switch code {
        case "zh-TW": return "Traditional Chinese"
        case "en-US": return "English"
        case "ja-JP": return "Japanese"
        case "ko-KR": return "Korean"
        default: return "Simplified Chinese"
        }
    }
}

/// 查表门面（各 View 经 Lang.t / Lang.tf 取文案；
/// 响应式刷新由 View 观察 LangStore 触发）。
enum Lang {
    static func t(_ key: String) -> String {
        LangStore.shared.lookup(key)
    }

    static func tf(_ key: String,
                   _ args: [String: String]) -> String {
        LangStore.shared.lookupf(key, args)
    }
}

// ── 诊断页（Web 口径：设置卡 + 当天卡 + 历史归档） ──
struct DiagView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var langStore: LangStore
    @ObservedObject private var diag = DiagLog.shared
    @StateObject private var ui = DiagUI()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diagAutodel") private var autodel = false
    @AppStorage("diagLevel") private var level = "all"
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17

    final class DiagUI: ObservableObject {
        @Published var levelOpen = false
        @Published var route: Route?
        @Published var shareURL: URL?
        enum Route: Identifiable {
            case today
            case archive(Int)
            var id: String {
                switch self {
                case .today: return "today"
                case .archive(let i): return "a\(i)"
                }
            }
        }
    }

    private var levelName: String {
        switch level {
        case "info": return Lang.t("diag.level_info")
        case "warn": return Lang.t("diag.level_warn")
        case "error": return Lang.t("diag.level_error")
        default: return Lang.t("diag.level_all")
        }
    }

    var body: some View {
        ChromeView(title: Lang.t("diag.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading,
                                   spacing: 2) {
                                Text(Lang.t("diag.autodel"))
                                    .font(.system(size: f16, weight: .semibold))
                                    .foregroundStyle(T.textMain)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { autodel },
                                set: { autodel = $0
                                       DiagLog.shared
                                           .applyAutodelete()
                                       // 页内动作留痕
                                       // （G6，Web set_
                                       // autodel 同口径）。
                                       DiagLog.shared.log(
                                           .info,
                                           "DIAG autodel -> "
                                           + "\($0 ? "on" : "off")") }))
                                .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        // 说明改行下独立说明行（F1，
                        // Web .diag-note）：11px 次级、
                        // 内距横 16 底 12、行高 1.45。
                        Text(Lang.t("diag.autodel_note"))
                            .font(.system(size: f11))
                            .lineSpacing(f11 * 0.45)
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        Rectangle()
                            .fill(T.borderSoft)
                            .frame(height: 0.5)
                            .padding(.horizontal, 16)
                        Button {
                            ui.levelOpen.toggle()
                        } label: {
                            HStack {
                                Text(Lang.t("diag.level"))
                                    .font(.system(size: f16, weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Spacer()
                                Text(levelName)
                                    .font(.system(size: f14))
                                    .foregroundStyle(
                                        T.textSecondary)
                                Text("›")
                                    .font(.system(size: f18))
                                    .foregroundStyle(T.textSecondary
                                        .opacity(0.45))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        if ui.levelOpen {
                            Picker(Lang.t("diag.level"),
                                   selection: Binding(
                                get: { level },
                                set: { level = $0
                                       // 页内动作留痕
                                       // （G6，Web set_
                                       // level_filter）。
                                       DiagLog.shared.log(
                                           .info,
                                           "DIAG level -> \($0)") })) {
                                Text(Lang.t("diag.level_all"))
                                    .tag("all")
                                Text(Lang.t("diag.level_info"))
                                    .tag("info")
                                Text(Lang.t("diag.level_warn"))
                                    .tag("warn")
                                Text(Lang.t("diag.level_error"))
                                    .tag("error")
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }
                    .glassCard(radius: Radius.panel)

                    // 节前距账（S2）：Web = 设置卡
                    // .backup-card margin-bottom 16 +
                    // page-gap 12 + .diag-today-head
                    // padding-top 4 = 32（卡底→标题
                    // 文字）。批 E 只对了头自身 4、
                    // 漏卡 margin 与 page-gap 两段。
                    SectionHeader(text: Lang.t("diag.today"),
                                  topPad: 32)

                    // 当天日志卡（F6 终端形态）：底 #111、
                    // 字 #7CFC9A、radius 28、padding 12、
                    // 11px 等宽行高 1.55；全量行卡内可滚
                    // （高上限约 52vh），整卡进视窗页。
                    Button {
                        ui.route = .today
                    } label: {
                        ScrollView {
                            // 行距合成（M6）：Web .diag-body
                            // 11px mono 行高 1.55 → 行间增
                            // 量 ≈6；统一 lineSpacing 6 +
                            // spacing 0（此前当天卡 6+2=8、
                            // 视窗页 6+3=9 且彼此不一致）。
                            VStack(alignment: .leading,
                                   spacing: 0) {
                                let lines = diagFiltered(
                                    diag.today, level: level)
                                if lines.isEmpty {
                                    Text(Lang.t("diag.empty"))
                                        // 此前无字体（继承
                                        // 环境默认 body）：
                                        // 按默认档等值收口
                                        // 喂点（fix_dynamic_
                                        // type_follow）。
                                        .font(.system(size: f17))
                                        .frame(
                                            maxWidth: .infinity,
                                            alignment: .center)
                                } else {
                                    ForEach(
                                        Array(lines
                                            .enumerated()),
                                        id: \.offset) { _, e in
                                        Text(e.line)
                                            .frame(
                                                maxWidth: .infinity,
                                                alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                        }
                        .frame(maxHeight: UIScreen.main.bounds
                            .height * 0.52)
                        .font(.system(size: f11,
                                      design: .monospaced))
                        .lineSpacing(6)
                        .foregroundStyle(T.termText)
                        .padding(12)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .background(
                            T.termBg,
                            in: RoundedRectangle(
                                cornerRadius: Radius.panel))
                    }
                    .buttonStyle(CardPressStyle())

                    // 全量一键导出（批 C）：当天 + 全部归
                    // 档拼一个文件走系统分享，不必逐页导。
                    Button {
                        exportEverything()
                    } label: {
                        HStack {
                            Image(systemName:
                                "square.and.arrow.up")
                                .font(.system(size: f14,
                                               weight: .semibold))
                            Text(Lang.t("diag.export_all"))
                                .font(.system(size: f14,
                                               weight: .semibold))
                            Spacer()
                            Text(Lang.t("diag.export_all_sub"))
                                .font(.system(size: f12))
                                .foregroundStyle(T.textSecondary)
                        }
                        .foregroundStyle(T.textMain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .glassCard(radius: Radius.panelS)
                    .padding(.top, 12)

                    SectionHeader(
                        text: Lang.t("diag.history"))
                    if diag.archives.isEmpty {
                        Text(Lang.t("diag.empty"))
                            .font(.system(size: f12))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   alignment: .center)
                            .padding(.horizontal, 4)
                    } else {
                        // 胶囊横向流式 wrap（F8）：内距
                        // 10/16、13px regular、glass-
                        // control 面、radius 999、gap 8。
                        FlowLayout(spacing: 8) {
                            ForEach(Array(diag.archives
                                .enumerated()), id: \.offset) {
                                idx, arch in
                                Button {
                                    ui.route = .archive(idx)
                                } label: {
                                    Text(arch.stamp)
                                        .font(.system(size: f13))
                                        .foregroundStyle(T.textMain)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .glassControl(radius: Radius.pill)
                                }
                                .buttonStyle(CardPressStyle())
                            }
                        }
                    }

                    // 库状态读数（真实库的实时事实，非自
                    // 检）：阶段 0 自检链的历史使命（在真
                    // 机证明 FFI 链可用）已于阶段 0 关单时
                    // 结束，且它跑临时目录、与真实库无关、
                    // 报告不入日志——按钮与报告已去除；
                    // FFI 函数本体保留给宿主 cargo test。
                    SectionHeader(text: Lang.t("diag.store"))
                    VStack(alignment: .leading, spacing: 6) {
                        DiagLine(Lang.t("diag.store_path"),
                                 library.storeDir)
                        DiagLine(Lang.t("diag.store_memos"),
                                 "\(library.memos.count)")
                        DiagLine(Lang.t("diag.store_attachments"),
                                 "\(library.attachmentCount())")
                        DiagLine(Lang.t("diag.store_hash"),
                                 library.libraryHash())
                        DiagLine(Lang.t("diag.store_cold"),
                                 library.timing)
                        // 数据自救动作（G14，只落零风险
                        // 两项，对位 Web repairBoot「只清
                        // 缓存不动数据」）：清天气缓存 +
                        // 只读校验库；真修复需 FFI 新接口
                        // 另行立项。
                        HStack(spacing: 10) {
                            Button(Lang.t("diag.clear_cache")) {
                                UserDefaults.standard
                                    .removeObject(
                                        forKey: "weatherCacheV1")
                                DiagLog.shared.log(.info,
                                    "DIAG cache cleared")
                            }
                            .font(.system(size: f13, weight: .semibold))
                            .foregroundStyle(T.accent)
                            Button(Lang.t("diag.verify_store")) {
                                if let v = library
                                    .verifyStore() {
                                    DiagLog.shared.log(.info,
                                        "DIAG verify memos="
                                        + "\(v.count) "
                                        + "hash=\(v.hash)")
                                } else {
                                    DiagLog.shared.log(.error,
                                        "DIAG verify failed")
                                }
                            }
                            .font(.system(size: f13, weight: .semibold))
                            .foregroundStyle(T.accent)
                        }
                        .padding(.top, 6)
                        // 手动救援入口（救援完整性批，
                        // P2-3）：正常模式下主动进安全
                        // 模式页，与 Web ?rescue=1 等
                        // 价——App 能跑但劣化时不必等
                        // streak 攒满。点击即经根分流切
                        // 换（enterRescueManually），不
                        // 动任何数据。
                        Button(Lang.t("diag.enter_rescue")) {
                            library.enterRescueManually()
                        }
                        .font(.system(size: f13, weight: .semibold))
                        .foregroundStyle(T.accent)
                        .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(16)
                    .glassCard(radius: Radius.panel)
                }
                // 宽屏收窄（AUD-C-02，用户 2026-11-28
                // 裁定）：原手抄三值与设置族内容框逐值
                // 等价，改经同一单点接入 720 收敛面；
                // 窄屏零变化。
                .settingsContentFrame()
            }
        }
        .onAppear { DiagLog.shared.loadIfNeeded() }
        .navigationDestination(isPresented: Binding(
            get: { ui.route != nil },
            set: { if !$0 { ui.route = nil } })) {
            switch ui.route {
            case .today:
                DiagLogPage(
                    stamp: Fmt.fullStamp(
                        Date().timeIntervalSince1970),
                    entries: diag.today)
            case .archive(let idx)
                where idx < diag.archives.count:
                DiagLogPage(
                    stamp: diag.archives[idx].stamp,
                    entries: diag.archives[idx].entries)
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        // 自检驱动注册（U5）：诊断页状态腿——自
        // 动清理开关动作与页内 Toggle 的 set 同
        // 体（写 AppStorage + applyAutodelete +
        // DIAG 留痕）；日志页经 openToday 同体进
        // 入（ui.route 写与行点按同）。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.diag", kind: "page",
                instance: "-",
                actions: [
                    "toggleAutodel": { d in
                        let v = (d ?? 0) > 0
                        autodel = v
                        DiagLog.shared
                            .applyAutodelete()
                        DiagLog.shared.log(.info,
                            "DIAG autodel -> "
                            + (v ? "on" : "off"))
                    },
                    "openToday": { _ in
                        ui.route = .today
                    },
                    "closeRoute": { _ in
                        ui.route = nil
                    },
                ],
                state: [
                    "autodel": {
                        autodel ? "true" : "false"
                    },
                    "level": { level },
                    "todayCount": {
                        "\(diag.today.count)"
                    },
                    "archiveCount": {
                        "\(diag.archives.count)"
                    },
                    "route": { ui.route?.id ?? "" },
                ])
        })
    }

    /// 导出环境头（G9）：导出文件自带设备/系统/库状
    /// 态，省去排障时回问机型版本。机型取 utsname
    /// machine（UIDevice.model 只有粗名不够定案）；
    /// 只入导出文件、不单独记 Diag 行。静态形供
    /// RescueView 共用（S3：安全模式导出走同一链）；
    /// library 未开库时 hash/计数走空值回退，不开库。
    static func envHeaderText(library: Library)
        -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let ver = info["CFBundleShortVersionString"]
            as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var uts = utsname()
        uname(&uts)
        let machine = withUnsafePointer(to: &uts.machine) {
            $0.withMemoryRebound(to: CChar.self,
                                 capacity: 1) {
                String(cString: $0)
            }
        }
        let os = ProcessInfo.processInfo
            .operatingSystemVersionString
        let hash = String(library.libraryHash().prefix(12))
        return """
        ==== 环境 ====
        app \(ver) (\(build))
        device \(machine) · \(os)
        store Application Support/library · memos \(library.memos.count) · attachments \(library.attachmentCount()) · hash \(hash)
        """
    }

    private var envHeader: String {
        Self.envHeaderText(library: library)
    }

    /// 全量导出组装（实例面与 RescueView 共用同一
    /// 链，S3）：环境头 + 归档旧→新 + 当天 + 附加段
    /// （救援侧传哨兵摘要段），写 tmp 返回 URL；失
    /// 败记 error 行返回 nil。只读 DiagLog 文件域，
    /// 不打开资料库。
    static func buildExportFile(
        library: Library,
        extraSections: [String]) -> URL? {
        let diag = DiagLog.shared
        var parts: [String] = [
            envHeaderText(library: library)]
        for arch in diag.archives.reversed() {
            parts.append("==== \(arch.stamp) ====")
            parts += arch.entries.map { $0.line }
        }
        parts.append("==== 今天 ====")
        parts += diag.today.map { $0.line }
        // S5 快照环整环附入（对位 Web W7 第三段）。
        parts.append(RescueLogStore.exportText())
        parts += extraSections
        let text = parts.joined(separator: "\n")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "此刻诊断_\(f.string(from: Date())).log")
        do {
            try text.write(to: url, atomically: true,
                           encoding: .utf8)
            return url
        } catch {
            DiagLog.shared.log(.error,
                "导出全部日志失败: \(error)")
            return nil
        }
    }

    /// 全量导出：归档旧→新在前、当天在后，逐段带戳
    /// 头；导出结局记一行（该行入当天日志、不入本次
    /// 文件，与 Web 导出记行同口径）。
    private func exportEverything() {
        guard let url = Self.buildExportFile(
            library: library, extraSections: [])
        else { return }
        DiagLog.shared.log(.info,
            "导出全部日志 archives="
            + "\(diag.archives.count) today="
            + "\(diag.today.count)")
        ui.shareURL = url
    }

    private func DiagLine(_ k: String, _ v: String)
        -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k)
                .font(.system(size: f13, weight: .semibold))
                .foregroundStyle(T.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(v)
                .font(.system(size: f12, design: .monospaced))
                .foregroundStyle(T.textMain)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

// ── 日志视窗页（Web 口径：标题 = 文件名，右上导出全量
// 未过滤行走系统分享） ─────────────────────────────
struct DiagLogPage: View {
    var stamp: String
    var entries: [DiagEntry]
    @EnvironmentObject private var langStore: LangStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = PageUI()
    @AppStorage("diagLevel") private var level = "all"
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17

    final class PageUI: ObservableObject {
        @Published var shareURL: URL?
    }

    private var fileName: String { "\(stamp).log" }

    var body: some View {
        GeometryReader { geo in
        ZStack(alignment: .top) {
            // 终端卡（G1）：底 #111、字 #7CFC9A、
            // radius 28、padding 12、11px 等宽/1.55，
            // 全行统一绿色（不再给 error 行红字）；
            // 卡撑满页头下可用区、卡内滚动。
            ScrollView {
                // 行距合成同诊断页当天卡（M6）：
                // lineSpacing 6 + spacing 0。
                VStack(alignment: .leading, spacing: 0) {
                    let lines = diagFiltered(entries,
                                              level: level)
                    if lines.isEmpty {
                        Text(Lang.t("diag.empty"))
                            .font(.system(size: f11,
                                          design: .monospaced))
                            .frame(maxWidth: .infinity,
                                   alignment: .center)
                    } else {
                        ForEach(Array(lines.enumerated()),
                                id: \.offset) { _, e in
                            Text(e.line)
                                .font(.system(size: f11,
                                              design: .monospaced))
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity,
                                       alignment: .leading)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(T.termText)
            .background(T.termBg,
                        in: RoundedRectangle(cornerRadius: Radius.panel))
            // 间距对齐设置页口径（用户 2026-11-28
            // 实报）：横 20 / 顶 81 / 底 40 与宽屏
            // 720 钳改经设置族内容框单点接入，不再
            // 手抄三值——顶距来源与设置页同源，口
            // 径调整一处生效两页。此前 AUD-C-02 只
            // 共用钳、三值仍自持（fix_diag_pages_
            // narrow），本批收完；页头行保持全宽
            // （与设置族页头同形态）。
            .settingsContentFrame()
            // 卡底距安全区项（S7）：Web .page-
            // content 底 padding = calc(40px +
            // safe)——内容框平 40 之上再叠安全区，
            // 卡下缘距视口底 40 + 安全区。终端卡
            // 全高贴底、与设置族滚动内容形态不
            // 同，此项单独保留、不入内容框单点。
            .padding(.bottom, geo.safeAreaInsets.bottom)
            HStack(alignment: .top) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: f17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: Radius.pill)
                }
                Spacer()
                CompactTitle(text: fileName)
                    .padding(.top, 4)
                Spacer()
                Button(action: exportAll) {
                    // 导出图标钮（用户 2026-11-28 实
                    // 报改判）：原文字胶囊（G2）改与
                    // 返回钮同形态的 46 圆玻璃图标钮
                    // 成对；符号 square.and.arrow.up
                    // 为全应用导出/分享统一符号
                    // （DiagView 导出卡 / 备份页导出
                    // 行 / 备忘分享菜单同符）。无障碍
                    // 标签仍读「导出」（diag.export
                    // 键转此一消费），导出行为与
                    // Diag 打点（exportAll 内 G6 行）
                    // 不变。
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: f17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: Radius.pill)
                }
                .accessibilityLabel(Lang.t("diag.export"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        // 自检驱动注册（U5）：日志视窗页结构读
        // 抽样（过滤后行数与总量、页戳）。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.diaglog",
                kind: "page",
                instance: "-",
                state: [
                    "stamp": { stamp },
                    "total": { "\(entries.count)" },
                    "lines": {
                        "\(diagFiltered(entries, level: level).count)"
                    },
                ])
        })
    }

    private func exportAll() {
        let text = entries.map { $0.line }
            .joined(separator: "\n")
        let safe = fileName.replacingOccurrences(
            of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe)
        // 成败留痕（G6）：此前 try? 静默，与导出全部
        // 一路有行一路无行不一致，统一记 DIAG 行。
        do {
            try text.write(to: url, atomically: true,
                           encoding: .utf8)
            DiagLog.shared.log(.info,
                "DIAG export ok \(safe) "
                + "\(text.utf8.count)B")
            ui.shareURL = url
        } catch {
            DiagLog.shared.log(.error,
                "DIAG export err \(safe): \(error)")
        }
    }
}

// ── 列表块（Web 口径：• / N. 标记 + 子项逐项编辑，
// 嵌套列表缩进续排；回车续项、空项回车退出、段首退格
// 并项走 EditorModel 的列表口径） ──────────────────
struct ListBlockView: View {
    @ObservedObject var block: BlockState
    var editor: EditorModel
    var depth: Int = 0

    // 文字大小布局韧性（impl_dt_layout_resilience）：
    // 标记框宽与嵌套缩进与标记字（callout）同源缩放
    // ——定宽 20 在大字号下两位数标记溢出框外、定值
    // 缩进与标记错位；默认档逐值不变（20/19/22）。
    @ScaledMetric(relativeTo: .callout)
    private var markerW: CGFloat = 20
    @ScaledMetric(relativeTo: .callout)
    private var indentBullet: CGFloat = 19
    @ScaledMetric(relativeTo: .callout)
    private var indentOrdered: CGFloat = 22
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(block.itemStates.enumerated()),
                    id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(marker(i))
                            .font(.system(size: f16))
                            .foregroundStyle(T.textMain)
                            .frame(width: markerW,
                                   alignment: .trailing)
                            .padding(.top, 3)
                        BlockTextView(
                            block: item, editor: editor,
                            listParent: block) {
                            block.nodeVersion += 1
                            editor.scheduleSave()
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                    }
                    if let nl = item.nestedList {
                        ListBlockView(block: nl, editor: editor,
                                      depth: depth + 1)
                            // 嵌套缩进（Web：ul 1.2em /
                            // ol 1.4em，线 1 #29；随标记
                            // 字同源缩放，见上 markerW 注）。
                            .padding(.leading,
                                     nl.type == "numbered-list"
                                        ? indentOrdered
                                        : indentBullet)
                    }
                }
            }
        }
    }

    private func marker(_ i: Int) -> String {
        if block.type == "numbered-list" {
            let attrs = block.node["attrs"] as? [String: Any]
            let start = attrs?["start"] as? Int ?? 1
            return "\(start + i)."
        }
        return "•"
    }
}

// ── 斜杠命令表（Web render.rs SLASH_CMDS 逐项移植：
// 标题/副标题存语言包键、呈现经 Lang.t 解析（I4 批
// 换键，与 Web 存键同构）；kw/py 为过滤全集） ──
struct SlashCmd {
    var act: String
    var oid: String
    /// 原版 type（过滤 haystack 一员，Web render.rs
    /// SLASH_CMDS.ty 逐项对表）。
    var ty: String
    var icon: String
    /// 标题/副标题存键（titleLangKey/subLangKey），
    /// title/sub 计算属性即解析面——rows 过滤/排序/
    /// 面板渲染等全部消费方零感知、随语言即时重演
    /// 算。字段名避与 PermKind.titleKey 同名（深检
    /// D4 按同名声明溯源、同名存储属性会遮蔽之）。
    var titleLangKey: String
    var subLangKey: String
    var title: String { Lang.t(titleLangKey) }
    var sub: String { Lang.t(subLangKey) }
    var shortcut: String
    var group: Int  // 0 基础、1 媒体
    var kw: String
    var py: String
}

enum SlashCmds {
    static let all: [SlashCmd] = [
        .init(act: "heading1", oid: "heading", ty: "heading", icon: "textformat.size", titleLangKey: "slash.heading1", subLangKey: "slash.heading1_sub", shortcut: "# ", group: 0, kw: "h1 heading 标题 一级", py: "bt1"),
        .init(act: "heading2", oid: "heading2", ty: "heading", icon: "textformat.size", titleLangKey: "slash.heading2", subLangKey: "slash.heading2_sub", shortcut: "## ", group: 0, kw: "h2 heading2 标题 二级", py: "bt2"),
        .init(act: "heading3", oid: "heading3", ty: "heading", icon: "textformat.size", titleLangKey: "slash.heading3", subLangKey: "slash.heading3_sub", shortcut: "### ", group: 0, kw: "h3 heading3 标题 三级", py: "bt3"),
        .init(act: "paragraph", oid: "paragraph", ty: "paragraph", icon: "text.alignleft", titleLangKey: "slash.paragraph", subLangKey: "slash.paragraph_sub", shortcut: "", group: 0, kw: "p paragraph 文本", py: "wb"),
        .init(act: "quote", oid: "quote", ty: "quote", icon: "quote.opening", titleLangKey: "slash.quote", subLangKey: "slash.quote_sub", shortcut: "> ", group: 0, kw: "q quote 引用", py: "yy"),
        .init(act: "todo", oid: "todo", ty: "todo", icon: "checklist", titleLangKey: "slash.todo", subLangKey: "slash.todo_sub", shortcut: "[ ] ", group: 0, kw: "t todo 待办", py: "db"),
        .init(act: "divider", oid: "divider", ty: "divider", icon: "minus", titleLangKey: "slash.divider", subLangKey: "slash.divider_sub", shortcut: "---", group: 0, kw: "d divider 分割线", py: "fgx"),
        .init(act: "bold", oid: "bold", ty: "inline_bold", icon: "bold", titleLangKey: "slash.bold", subLangKey: "slash.bold_sub", shortcut: "** **", group: 0, kw: "b bold 加粗 粗体", py: "jc"),
        .init(act: "italic", oid: "italic", ty: "inline_italic", icon: "italic", titleLangKey: "slash.italic", subLangKey: "slash.italic_sub", shortcut: "* *", group: 0, kw: "i italic 斜体 倾斜", py: "xt"),
        .init(act: "highlight", oid: "highlight", ty: "inline_highlight", icon: "highlighter", titleLangKey: "slash.highlight", subLangKey: "slash.highlight_sub", shortcut: "== ==", group: 0, kw: "h highlight 高亮", py: "gl"),
        .init(act: "codeBlock", oid: "codeBlock", ty: "code_block", icon: "chevron.left.forwardslash.chevron.right", titleLangKey: "slash.code_block", subLangKey: "slash.code_block_sub", shortcut: "```", group: 0, kw: "code codeblock 代码块", py: "dmk"),
        .init(act: "mathBlock", oid: "mathBlock", ty: "math_block", icon: "sum", titleLangKey: "slash.math_block", subLangKey: "slash.math_block_sub", shortcut: "$$", group: 0, kw: "math formula block 公式块", py: "gsk"),
        .init(act: "bulletList", oid: "unorderedList", ty: "unordered_list", icon: "list.bullet", titleLangKey: "slash.bullet_list", subLangKey: "slash.bullet_list_sub", shortcut: "- ", group: 0, kw: "list ul 无序列表 列表", py: "wxl"),
        .init(act: "numberList", oid: "orderedList", ty: "ordered_list", icon: "list.number", titleLangKey: "slash.number_list", subLangKey: "slash.number_list_sub", shortcut: "1. ", group: 0, kw: "ol list 有序列表 列表", py: "yxl"),
        .init(act: "callout", oid: "callout", ty: "callout", icon: "exclamationmark.bubble", titleLangKey: "slash.callout", subLangKey: "slash.callout_sub", shortcut: "> [!]", group: 0, kw: "callout note tip warning 提示 警告", py: "callout"),
        .init(act: "link", oid: "link", ty: "inline_link", icon: "link", titleLangKey: "slash.link", subLangKey: "slash.link_sub", shortcut: "[](url)", group: 0, kw: "l link 链接 超链接", py: "lj"),
        .init(act: "code", oid: "code", ty: "inline_code", icon: "chevron.left.forwardslash.chevron.right", titleLangKey: "slash.code", subLangKey: "slash.code_sub", shortcut: "` `", group: 0, kw: "c code 代码 内联", py: "dm"),
        .init(act: "mathInline", oid: "mathInline", ty: "inline_math", icon: "function", titleLangKey: "slash.math_inline", subLangKey: "slash.math_inline_sub", shortcut: "$ $", group: 0, kw: "math formula inline 公式 行内", py: "gs"),
        .init(act: "strikethrough", oid: "strikethrough", ty: "inline_strike", icon: "strikethrough", titleLangKey: "slash.strikethrough", subLangKey: "slash.strikethrough_sub", shortcut: "~~ ~~", group: 0, kw: "s strike strikethrough 删除线", py: "scx"),
        .init(act: "imgTextCard", oid: "imgTextCard", ty: "imgTextCard", icon: "doc.richtext", titleLangKey: "slash.img_text_card", subLangKey: "slash.img_text_card_sub", shortcut: "", group: 1, kw: "image text card 图文 卡片", py: "twkp"),
        .init(act: "imageTextRow", oid: "imageTextRow", ty: "imageTextRow", icon: "rectangle.split.2x1", titleLangKey: "slash.image_text_row", subLangKey: "slash.image_text_row_sub", shortcut: "", group: 1, kw: "image text row 图文 混排 左右", py: "twhp"),
        .init(act: "musicCard", oid: "musicCard", ty: "musicCard", icon: "music.note", titleLangKey: "slash.music_card", subLangKey: "slash.music_card_sub", shortcut: "", group: 1, kw: "m music 音乐 卡片", py: "yykp"),
        .init(act: "image", oid: "image", ty: "image", icon: "photo", titleLangKey: "slash.image", subLangKey: "slash.image_sub", shortcut: "", group: 1, kw: "i image 图片", py: "tp"),
        .init(act: "gallery", oid: "gallery", ty: "gallery", icon: "photo.on.rectangle.angled", titleLangKey: "slash.gallery", subLangKey: "slash.gallery_sub", shortcut: "", group: 1, kw: "g gallery 画廊", py: "hl"),
    ]

    /// 面板行单源（Web render.rs SlashPanel 的 rows
    /// 构成）：面板渲染、首帧估高、键盘导航三方共用
    /// 同一序列——组头行 + 命令行（cidx = 命令行序，
    /// 选中态按此索引）。空查询 = 最近（置顶）+ 基
    /// 础/媒体两组（组内剔除最近）；有查询 = 命中重
    /// 排（Web 口径）：hay = title+sub+kw+ty+py 小
    /// 写 contains；前缀命中（title+kw 或 py 前缀）
    /// 优先、余按标题 localeCompare zh-Hans-CN。
    enum Row {
        case head(String)
        case cmd(SlashCmd, recent: Bool, cidx: Int)
    }

    static func normQuery(_ q: String) -> String {
        q.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func rows(_ q: String) -> [Row] {
        let query = normQuery(q)
        var out: [Row] = []
        var cidx = 0
        if query.isEmpty {
            let recents = recents()
            let recentActs = Set(recents.map(\.act))
            if !recents.isEmpty {
                out.append(.head(Lang.t("slash.recent")))
                for c in recents {
                    out.append(.cmd(c, recent: true,
                                    cidx: cidx))
                    cidx += 1
                }
            }
            for (g, key) in [(0, "slash.group_basic"),
                             (1, "slash.group_media")] {
                let items = all.filter {
                    $0.group == g
                        && !recentActs.contains($0.act)
                }
                if items.isEmpty { continue }
                out.append(.head(Lang.t(key)))
                for c in items {
                    out.append(.cmd(c, recent: false,
                                    cidx: cidx))
                    cidx += 1
                }
            }
            return out
        }
        var hits = all.filter { c in
            (c.title + " " + c.sub + " " + c.kw + " "
                + c.ty + " " + c.py)
                .lowercased().contains(query)
        }
        hits.sort { a, b in
            func starts(_ c: SlashCmd) -> Int {
                ((c.title + " " + c.kw).lowercased()
                    .hasPrefix(query)
                    || c.py.hasPrefix(query)) ? 0 : 1
            }
            let sa = starts(a), sb = starts(b)
            if sa != sb { return sa < sb }
            return a.title.compare(
                b.title,
                locale: Locale(identifier: "zh-Hans-CN"))
                == .orderedAscending
        }
        for c in hits {
            out.append(.cmd(c, recent: false, cidx: cidx))
            cidx += 1
        }
        return out
    }

    /// 行序中的命令列（键盘导航/回车执行按 slashSel
    /// 索引此列）。
    static func rowCommands(_ q: String) -> [SlashCmd] {
        rows(q).compactMap { r in
            if case .cmd(let c, _, _) = r { return c }
            return nil
        }
    }

    /// 命中切分（Web slash_hl_parts 逐字移植）：首
    /// 个大小写不敏感命中切 pre/mid/post；q 须已规
    /// 范化（小写）；文本字符的小写形须恰为单字符
    /// 且与 q 对应字符全等。无命中 mid = nil。
    static func hlParts(_ text: String, _ q: String)
        -> (pre: String, mid: String?, post: String) {
        let miss = (text, nil as String?, "")
        if q.isEmpty || text.isEmpty { return miss }
        let t = Array(text)
        let p = Array(q)
        if p.isEmpty || p.count > t.count { return miss }
        outer: for i in 0...(t.count - p.count) {
            for (j, qc) in p.enumerated() {
                let low = String(t[i + j]).lowercased()
                if low.count != 1
                    || low.first != qc {
                    continue outer
                }
            }
            return (String(t[..<i]),
                    String(t[i..<(i + p.count)]),
                    String(t[(i + p.count)...]))
        }
        return miss
    }

    static func recents() -> [SlashCmd] {
        let ids = UserDefaults.standard
            .stringArray(forKey: "slashRecentOids") ?? []
        return ids.compactMap { oid in
            all.first { $0.oid == oid }
        }
    }

    static func recordRecent(_ act: String) {
        guard let cmd = all.first(where: { $0.act == act })
        else { return }
        var ids = UserDefaults.standard
            .stringArray(forKey: "slashRecentOids") ?? []
        ids.removeAll { $0 == cmd.oid }
        ids.insert(cmd.oid, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(6)),
                                  forKey: "slashRecentOids")
    }
}

// ── 编辑器 ─────────────────────────────────────────
struct ImageTarget: Identifiable {
    let id = UUID()
    var fileId: String?
    var urlString: String?
    var name: String
}

/// 编辑页滚动状态（独立对象）：scrollY 的发布只失效
/// 观察它的页眉子树。教训——ObservableObject 订阅是
/// 对象粒度，scrollY 与 EditorUI 共居一对象时，滚动
/// 逐帧发布会连带整个编辑页重演算（0.9.6 隔离无效
/// 的根源，三线审计定案）。
final class EditorScrollState: ObservableObject {
    @Published var scrollY: CGFloat = 0
    var maxScrollY: CGFloat = 0
    /// 静止基线（首个有效探针值捕获）与捕获时的形态；
    /// 形态切换即作废重捕。0.9.9 曾改常数 168 推算，
    /// 与真机探针实际静止值不符、页眉开篇即紧凑——
    /// 退回捕获制（0.9.7 真机形态）并加两道守卫。
    var baseY: CGFloat?
    var baseMode = -1
    /// SCROLL 轨迹打点节流（诊断用）：上次记行值与时刻。
    var traceY: CGFloat = .nan
    var traceAt: Date = .distantPast
}

final class EditorModel: ObservableObject {
    let scrollState = EditorScrollState()
    @Published var title: String
    @Published var blocks: [BlockState]
    @Published var draggingId: String?
    @Published var dragDy: CGFloat = 0
    /// 落位回弹（M20）：drop 后被拖块在新位的起始偏
    /// 移，弹簧归零（settleId 标记块、settleDy 偏移）。
    @Published var settleId: String?
    @Published var settleDy: CGFloat = 0
    @Published var imageTarget: ImageTarget?
    /// 图片页路由单点（fix_image_tap_regression）：
    /// 全部可开面（图块/gallery 瓦/附件整幅图与
    /// 图片文件行/图文卡图区）的点按恒经此置位
    /// imageTarget、呈现由转场宿主订阅单点承接；
    /// 无名回退（imgpage.untitled）在此收口，各
    /// 面不再自拼 ImageTarget——路由全集以本函
    /// 数调用点普查为准（verify [70] 锁）。
    func presentImagePage(fileId: String?,
                          urlString: String?,
                          name: String?) {
        imageTarget = ImageTarget(
            fileId: fileId, urlString: urlString,
            name: name ?? Lang.t("imgpage.untitled"))
    }
    @Published var bgColor: String?
    /// 双栏布局锚（Web MemoLayout 口径）：{version, mode,
    /// left, right}，left/right 为两栏块 id 名单；persist
    /// 时写回 raw["layout"]，与 Web 互通同一字段。
    @Published var layout: [String: Any]?
    /// 双栏独立滚动模式（true=independent、false=flow）。
    /// 决议序同 Web：layout.mode 在位优先；有 layout 无
    /// mode 默认 independent（G-2）；无 layout 读用户默认。
    @Published var twoPaneIndependent = false
    /// 当前是否处于宽屏双栏呈现（EditorView 同步进来，
    /// 供拖拽栏内钳制与落锚判定）。
    var columnsActive = false
    private var anchorCaptureDone = false
    @Published var focusBlockId: String?
    @Published var focusCaretEnd = false
    @Published var editingBlockId: String?
    /// 跨块虚拟选区（F-09 一期，MomentXSel.swift /
    /// MomentXSelBridge.swift）：模型层选区状态单
    /// 点，桥接层状态机维护；nil = 无跨块选区（原
    /// 生选区收拢在锚点块内）。
    @Published var xsel: XSel?
    /// 原子块选中态（F-08，Web sel_block 同位）：段
    /// 首退格撞原子前驱时置位、行面描边呈现；纯视
    /// 图态不落盘，键盘永不据此删块（Web 选中态下
    /// 退格/删除一律无操作、删块走卡菜单明路）。
    /// 清除面：进入文本编辑（didBeginEditing）、选
    /// 中块被删、再次退格撞另一原子块时覆写。
    @Published var selectedBlockId: String?
    /// 空图占位点按 → 选图替换该块（EditorView 呈现）。
    @Published var showReplacePicker = false
    var replaceImageBlockId: String?

    func replaceImage(fileId: String) {
        guard let id = replaceImageBlockId,
              let b = blocks.first(where: { $0.id == id })
        else { return }
        pushHistory()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        attrs["fileId"] = fileId
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        replaceImageBlockId = nil
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT card replace image \(id) fid=\(fileId)")
    }

    // ── 卡片浮层菜单 + 卡编辑态（F1/F2，Web layers.rs
    // CardMenuLayer 口径）──
    // 卡片防误触机制的成员单点：拾起菜单路由（BlockRow
    // .isCardType）与结构守卫分类（BlockState
    // .isStructuralAtomic）同集消费——成员的编辑/删除
    // 只经拾起卡菜单、键盘永不删除/溶解成员。基线 =
    // Web CARD_MENU_TYPES 九型；codeBlock 与
    // embedCard 为原生扩展（用户 2026-11-28 指令：
    // 代码块接入本机制 + 全块型普查归一，定案
    // impl_card_guard_unify.md）：codeBlock 是源码态
    // 字面块（Web B11 同类），embedCard 是原子兜底
    // 块、二者原先游离于集外（代码块走文本合并流四
    // 向可溶解、embedCard 拾起误走块菜单）。与 Web
    // 的此两处差异为有意偏离、报告在案。其中可进编
    // 辑态/有编辑动作的为 editCardTypes（Web
    // has_edit 名单），musicCard 的「编辑」是即时输
    // URL 动作、不设持续编辑态；新成员不入
    // editCardTypes——菜单只出「删除此块」（与
    // divider/attachment/video/link-card 同形态），
    // 代码块打字编辑仍是点按直入（其主功能路径）。
    static let cardMenuTypes: Set<String> = [
        "imgTextCard", "imageTextRow", "image", "gallery",
        "musicCard", "link-card", "attachment", "video",
        "divider", "codeBlock", "embedCard",
    ]
    static let editCardTypes: Set<String> = [
        "imgTextCard", "imageTextRow", "image", "gallery",
        "musicCard",
    ]
    @Published var cardMenuBlockId: String?
    @Published var cardEditBlockId: String?
    /// 块类型转换菜单（0.9.47）：由按压引擎拾起呈现
    /// （替代已删的 .contextMenu），状态与呈现见
    /// EditorView.blockMenuLayer。
    @Published var blockMenuBlockId: String?

    func exitCardEdit(via: String) {
        guard let id = cardEditBlockId else { return }
        cardEditBlockId = nil
        // 图库排序会话随卡编辑态收口（F-14）：防拖拽
        // 中途退出后 armed 旗残留、下一拖漏压历史。
        endGalleryReorder()
        DiagLog.shared.log(.info,
            "EDIT card edit exit \(id) (\(via))")
    }

    // 图库选图（编辑态）：add = 多选追加、replace =
    // 单选换指定张；状态由 EditorView 的 sheet 消费。
    @Published var showGalleryAddPicker = false
    @Published var showGalleryReplacePicker = false
    var galleryPickBlockId: String?
    var galleryReplaceIndex: Int?

    func applyGalleryAdd(blockId: String, fileIds: [String]) {
        guard let b = blocks.first(where: { $0.id == blockId }),
              !fileIds.isEmpty else { return }
        pushHistory()
        endGalleryReorder()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        for fid in fileIds {
            items.append(["fileId": fid])
        }
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery add \(blockId) +\(fileIds.count)")
    }

    func applyGalleryReplace(blockId: String, index: Int,
                             fileId: String) {
        guard let b = blocks.first(where: { $0.id == blockId })
        else { return }
        pushHistory()
        endGalleryReorder()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        guard items.indices.contains(index) else { return }
        items[index] = ["fileId": fileId]
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery replace \(blockId) idx=\(index)")
    }

    /// 图库删项（F-14，2026-11-27 裁定原生增强；Web
    /// 同缺）：只摘节点里的项引用——附件字节与清单
    /// 登记不删（现行口径：FFI 无附件删除面，换图/
    /// 删块同样只摘引用、字节留存待备份层处理），与
    /// applyGalleryReplace 的旧图处置同轨。删空后回
    /// GalleryBlockView 的空态双占位（加图路现成）。
    func applyGalleryRemove(blockId: String, index: Int) {
        guard let b = blocks.first(where: { $0.id == blockId })
        else { return }
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        guard items.indices.contains(index) else { return }
        pushHistory()
        endGalleryReorder()
        items.remove(at: index)
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery remove \(blockId) idx=\(index)"
            + " left=\(items.count)")
    }

    /// 图库排序会话（F-14）：编辑态瓦长按拖拽期间的
    /// 实时换位。历史只在会话首动压一次（一拖 = 一
    /// 个撤销步，与块拖拽 commitDrag 的单步口径同）；
    /// 会话由 endGalleryReorder / 退出卡编辑态收口，
    /// 其余离散操作（加/换/删）自带压栈、亦复位此旗。
    private var galleryReorderArmed = false
    /// 拖拽中的源瓦位（拖起时写、dropEntered 链式
    /// 跟进、会话收口清零）：同进程内拖拽的源位传
    /// 递走模型侧会话变量，不经 NSItemProvider 异
    /// 步读回。
    var galleryDragTileIndex: Int?

    func applyGalleryMove(blockId: String, from: Int,
                          to: Int) {
        guard from != to,
              let b = blocks.first(where: { $0.id == blockId })
        else { return }
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        var items = attrs["items"] as? [[String: Any]] ?? []
        guard items.indices.contains(from),
              items.indices.contains(to) else { return }
        if !galleryReorderArmed {
            pushHistory()
            galleryReorderArmed = true
        }
        let it = items.remove(at: from)
        items.insert(it, at: to)
        attrs["items"] = items
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT gallery move \(blockId) \(from)->\(to)")
    }

    func endGalleryReorder() {
        galleryReorderArmed = false
        galleryDragTileIndex = nil
    }
    let item: MemoItem
    let library: Library
    private var saveWork: DispatchWorkItem?

    // 撤销/重做历史（E2 根治，审计 F-10/F-11）：记
    // 账单点 UndoHistoryCore（MomentUndo.swift）——
    // 返回点记录（去重 + 上限 100）+ 文本爆发合并
    // （600ms）+ 条目附选区快照（恢复用）。旧形态
    // （两裸数组、上限 50、无去重、粒度 = 整个聚
    // 焦会话、恢复不带焦点）整套退役。
    private var history = UndoHistoryCore<[String: Any]>()
    @Published var canUndo = false
    @Published var canRedo = false

    /// 新建篇初始落焦意图（创建方置位）：由首个文本
    /// 块视图认领（BlockTextView.updateUIView），不经
    /// EditorView.onAppear 的状态往返。0.9.50 呈现重
    /// 构起认领须先过转场门（focusGateOpen）：旧形态
    /// 在安装帧（push 第 0 帧）即认领，键盘动画与转
    /// 场全程重叠成两段感；现由转场宿主在转场
    /// completion 后开门，键盘在页面落定后单独升起。
    var wantsInitialFocus = false

    /// 转场认领门（0.9.50）：宿主在 push 转场落定后
    /// 经 openFocusGate 打开；门未开时块视图不认领。
    /// tick 为发布型推手——开门时 +1 触发一轮块视图
    /// 更新，认领仍走 BlockTextView.claimInitialFocus
    /// 单点实现（成功校验/有界重试/记账都在那里）。
    var focusGateOpen = false
    @Published var focusGateTick = 0

    func openFocusGate() {
        focusGateOpen = true
        focusGateTick += 1
    }

    /// 转场落定发布（补丁债偿还批一 A-7）：宿主在
    /// 每次呈现的转场落定单点（transitionCompleted，
    /// push 落定与关联替换同点）经 noteTransition-
    /// Settled 推一拍。编辑页「落定后才做」的事项
    /// （••• 菜单整树惰性预建）挂此事件——旧制以
    /// EditorView.onAppear + 0.6s 经验常数定时近
    /// 似（onAppear 在转场前构建期即触发、与落定
    /// 无因果关系），已删。
    @Published var settleTick = 0

    func noteTransitionSettled() {
        settleTick += 1
    }

    // ── CREATE 计时（新建→编辑页首帧分段量测）──
    /// 四个时刻点：建篇起/止（Library.create 两端）、
    /// 模型 init 止、EditorView 出现、初始落焦认领。
    /// 仅当本篇是刚新建的那篇时 init 认领计时痕；
    /// 纯读时钟打点，不改任何业务时序。
    var traceCreateStart: CFAbsoluteTime = 0
    var traceCreateEnd: CFAbsoluteTime = 0
    var traceInitEnd: CFAbsoluteTime = 0
    var traceAppear: CFAbsoluteTime = 0
    var traceFocusLogged = false
    /// 分段点（0.9.48 补齐，第二轮排查第六节）：置
    /// 位点 dest、认领成功/收口点 claim、键盘落定近
    /// 似点 kb、EditorView body 轮数 bodypass、settle
    /// 总账。基点未记（== 0）时对应段输出 na，绝不
    /// 以 0 为基点算出量级巨值（旧 focus 段缺陷）。
    var traceDest: CFAbsoluteTime = 0
    var traceClaim: CFAbsoluteTime = 0
    /// 认领结果位（settle 的 claim 段以 ok/inwindow
    /// 形态出，0.9.50 规范化——旧形态印 ms 值、认领
    /// 未达时成「claim=nams」不可判读）。
    var traceClaimOk = false
    var traceClaimInWindow = false
    var traceKb: CFAbsoluteTime = 0
    var traceBodyPasses = 0
    var traceClaimLogged = false
    var traceSettleLogged = false
    /// 初始落焦认领已失败次数（有界重试 ≤3，见
    /// BlockTextView.claimInitialFocus）。
    var createClaimAttempts = 0

    /// 分段毫秒（0.9.48 口径）：两端基点都已记且
    /// 后者晚于前者才出数，否则 "na"——取代旧 ms()
    /// 的 -1/巨值双缺陷（基点未记时旧实现以 0 为基
    /// 点返回 Int(now×1000) 量级假数，focus 段曾不
    /// 可作判据，第二轮排查第六节定案）。
    private func traceMs(_ a: CFAbsoluteTime,
                         _ b: CFAbsoluteTime) -> String {
        (a > 0 && b > a)
            ? "\(Int((b - a) * 1000))" : "na"
    }

    /// 置位点（四新建入口在 nav.dest 置位后调用）：
    /// 把 pre 段切成「建篇+模型」与「置位→出现」。
    func noteCreateDest() {
        guard traceCreateStart > 0, traceDest == 0
        else { return }
        traceDest = CFAbsoluteTimeGetCurrent()
        DiagLog.shared.log(.info,
            "CREATE dest id=\(item.id) "
            + "model2dest=\(traceMs(traceInitEnd, traceDest))ms")
    }

    /// 认领收口点（成功或有界重试耗尽时调用）：ok
    /// 位 + 认领时刻，S4 脆弱点（静默丢失）据此与
    /// 「一次成功」分辨。
    func recordCreateClaim(ok: Bool, inWindow: Bool) {
        guard traceCreateStart > 0, !traceClaimLogged
        else { return }
        traceClaimLogged = true
        traceClaim = CFAbsoluteTimeGetCurrent()
        traceClaimOk = ok
        traceClaimInWindow = inWindow
        DiagLog.shared.log(.info,
            "CREATE claim id=\(item.id) "
            + "ok=\(ok ? 1 : 0) "
            + "inwindow=\(inWindow ? 1 : 0)")
    }

    /// 键盘落定近似点（EditorView 背景读数 safeArea
    /// Insets.bottom 首次由 0 变非零时调用）。
    func noteCreateKb() {
        guard traceCreateStart > 0, traceKb == 0
        else { return }
        traceKb = CFAbsoluteTimeGetCurrent()
        DiagLog.shared.log(.info,
            "CREATE kb id=\(item.id) "
            + "dest2kb=\(traceMs(traceDest, traceKb))ms")
    }

    /// EditorView body 轮数（S2 量测）：body 入口
    /// 每轮 +1，settle 行汇总。
    func noteBodyPass() {
        guard traceCreateStart > 0 else { return }
        traceBodyPasses += 1
    }

    /// 出现点（EditorView.onAppear 调用）：记出现
    /// 时刻，先出一行 create/pre 两段；并约 0.5s 后
    /// 出 settle 总账（转场 0.35s + 键盘落定都在窗
    /// 内，一行定案四嫌疑）。
    func markCreateAppear() {
        guard traceCreateStart > 0, traceAppear == 0
        else { return }
        traceAppear = CFAbsoluteTimeGetCurrent()
        let createMs = Int((traceCreateEnd
            - traceCreateStart) * 1000)
        let preMs = Int((traceAppear
            - traceCreateEnd) * 1000)
        DiagLog.shared.log(.info,
            "CREATE appear id=\(item.id) "
            + "create=\(createMs)ms pre=\(preMs)ms")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5) { [weak self] in
            self?.logCreateSettle()
        }
    }

    /// 落焦收口（初始落焦认领成功点调用）：全程分
    /// 段一行出齐——create=建篇（落盘+入列）、model=
    /// 模型构造、appear=模型→出现、focus=置位→认
    /// 领（0.9.48 改基点：旧口径以出现点为基，认领
    /// 早于出现点时基点未记会算出巨值；现基点未记
    /// 一律 na）。
    func logCreateFocusTiming() {
        guard traceCreateStart > 0, !traceFocusLogged
        else { return }
        traceFocusLogged = true
        DiagLog.shared.log(.info,
            "CREATE timing id=\(item.id) "
            + "create=\(traceMs(traceCreateStart, traceCreateEnd))ms "
            + "model=\(traceMs(traceCreateEnd, traceInitEnd))ms "
            + "appear=\(traceMs(traceInitEnd, traceAppear))ms "
            + "focus=\(traceMs(traceDest, traceClaim))ms")
    }

    /// settle 总账（onAppear 后 0.5s，markCreateAppear
    /// 约定）：create/model/dest/appear 分段 + 列表
    /// 归组趟数与总耗时 + 头像 FFI 耗时 + 编辑页
    /// body 轮数 + claim/kb 段，一行定案；收口后清
    /// Library 的量测开账旗。
    func logCreateSettle() {
        guard traceCreateStart > 0, !traceSettleLogged
        else { return }
        traceSettleLogged = true
        let lib = library
        let avatarSeg = lib.createTraceAvatarMs >= 0
            ? "\(lib.createTraceAvatarMs)" : "na"
        // claim 段口径（0.9.50 规范化）：与 CREATE
        // claim 行同形态 ok/inwindow；认领未达（戳未
        // 记）输出 na，不再印无判读意义的 ms 值。
        let claimSeg = traceClaim > 0
            ? "ok\(traceClaimOk ? 1 : 0)"
              + "/inwindow\(traceClaimInWindow ? 1 : 0)"
            : "na"
        DiagLog.shared.log(.info,
            "CREATE settle id=\(item.id) "
            + "create=\(traceMs(traceCreateStart, traceCreateEnd))ms "
            + "model=\(traceMs(traceCreateEnd, traceInitEnd))ms "
            + "dest=\(traceMs(traceInitEnd, traceDest))ms "
            + "appear=\(traceMs(traceDest, traceAppear))ms "
            + "listpass=\(lib.createTraceListPasses)x"
            + "\(lib.createTraceListMs)ms "
            + "avatar=\(avatarSeg)ms "
            + "bodypass=\(traceBodyPasses) "
            + "claim=\(claimSeg) "
            + "kb=\(traceMs(traceDest, traceKb))ms")
        lib.createTraceActive = false
    }

    init(item: MemoItem, library: Library) {
        // E4 量测点：init 全程计时（普查行出，见 init 末）。
        let initT0 = CFAbsoluteTimeGetCurrent()
        self.item = item
        self.library = library
        // 撤销引擎本体打点接线（AUD-E-05①）：引擎
        // 内部分支（去重/钳制逐出/空栈步进）经
        // eventSink 自记，Diag 词形在此单点承接；
        // 消费方代记（旧馈入代记两支）已删
        // 除收敛，防双记。
        history.eventSink = { event in
            DiagLog.shared.log(.info,
                "EDIT undo core " + event)
        }
        title = item.title
        blocks = item.blocks
        bgColor = item.bgColor
        // 双栏决议（Web hooks/columns.rs 口径）：mode 在位
        // 优先；有 layout 无 mode 默认 independent（G-2）；
        // 无 layout 读用户级默认（开关切换时写入）。
        let rawLayout = item.raw["layout"] as? [String: Any]
        layout = rawLayout
        if let mode = rawLayout?["mode"] as? String {
            twoPaneIndependent = (mode == "independent")
        } else if rawLayout != nil {
            twoPaneIndependent = true
        } else {
            twoPaneIndependent = UserDefaults.standard.bool(
                forKey: "editorIndependentScroll")
        }
        // 空文档打开守卫（E4/F-19①）：空 doc 无块即无
        // 落焦入口的死页——打开路径补空段（删块路径同
        // 守卫，见 deleteBlock），与 Web 空 doc 有插段/
        // 落焦路径的口径对齐。物化随原子尾随同路异步
        // 落盘（只读态 persist 自有 writeBlocked 闸、
        // 无副作用）。
        if blocks.isEmpty {
            blocks.append(BlockState(
                node: Self.emptyParagraphNode()))
            DiagLog.shared.log(.info,
                "EDIT empty doc seeded memo=\(item.id)")
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSave()
            }
        }
        // 原子块收尾时物化尾随空段（Web 口径）：末尾恒有
        // 可落焦的文本段，不必点原子块才能续写。
        if let last = blocks.last,
           BlockKind.isTrailEndAtomic(last.type) {
            blocks.append(BlockState(
                node: Self.emptyParagraphNode()))
            DispatchQueue.main.async { [weak self] in
                self?.scheduleSave()
            }
        }
        // 卡片补拉（Web hydrate 口径）：有 url、未就绪的
        // 音乐/链接卡打开时补走解析链。
        let pending = blocks.filter {
            ($0.type == "musicCard" || $0.type == "link-card")
                && ($0.node["url"] as? String)
                    .map({ !$0.isEmpty }) ?? false
                && !["ready", "input", "loading"].contains(
                    $0.node["status"] as? String ?? "")
        }
        if !pending.isEmpty {
            DispatchQueue.main.async { [weak self] in
                for b in pending {
                    var n = b.node
                    n["status"] = "loading"
                    b.node = n
                    b.nodeVersion += 1
                    self?.startResolveCard(b)
                }
            }
        }
        // MD 块级预览段的尾随空段物化（打开时先行一趟，
        // 与 Web init 口径一致）。
        materializeMdTrails()
        // CREATE 计时认领：本篇恰为刚新建的那篇时取
        // 走计时痕（按 id 对位），普通打开零命中。
        if let tr = library.consumeCreateTrace(
            for: item.id) {
            traceCreateStart = tr.start
            traceCreateEnd = tr.end
            traceInitEnd = CFAbsoluteTimeGetCurrent()
        }
        // E4 长文档量测普查（F-19② 的自变量面）：打开
        // 每篇一行的块构成普查——UITextView 实例数 ≈
        // text + callout + listItems（呈现层全量 VStack
        // 实例化、无窗口化）；因变量（首帧构建耗时）
        // 读同 id 的 TRANSITION build= 段。样本口径与
        // 护栏裁定见 impl_editor_robust_e4.md。
        let censusText = blocks.filter { $0.isText }.count
        let censusCallout = blocks.filter {
            $0.type == "callout" }.count
        let censusItems = blocks.filter { $0.isList }
            .reduce(0) { $0 + $1.itemStates.count }
        let censusAtomic = blocks.filter {
            BlockKind.isTrailEndAtomic($0.type) }.count
        let censusUnknown = blocks.filter {
            !$0.isText && !$0.isList
                && !BlockKind.censusKnown.contains($0.type)
        }.count
        let censusChars = blocks.reduce(0) {
            $0 + Self.plainText(of: $1).count }
        let censusInitMs = Int(
            (CFAbsoluteTimeGetCurrent() - initT0) * 1000)
        DiagLog.shared.log(.info,
            "EDIT open census memo=\(item.id) "
            + "blocks=\(blocks.count) "
            + "text=\(censusText) "
            + "callout=\(censusCallout) "
            + "listItems=\(censusItems) "
            + "atomic=\(censusAtomic) "
            + "unknown=\(censusUnknown) "
            + "chars=\(censusChars) "
            + "init=\(censusInitMs)ms")
    }

    /// 空段落节点（三处共用、形状单点：打开守卫/原子
    /// 尾随物化/删块兜底——防三处字面漂移）。
    static func emptyParagraphNode() -> [String: Any] {
        [
            "id": "b-" + UUID().uuidString.prefix(8)
                .lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ]
    }

    // ── 双栏分界（Web editor/columns.rs 逐项移植） ──
    /// 块的纯文本（递归含列表项，与 Web plain_text 口径
    /// 一致，供估高折行）。
    static func plainText(of b: BlockState) -> String {
        var s = b.text
        for it in b.itemStates { s += plainText(of: it) }
        if let n = b.nestedList { s += plainText(of: n) }
        return s
    }

    /// 规范估高（Web est_block_height 回退表）：图片/画廊
    /// /图文卡 280，音乐/链接/嵌入卡 120，附件带图 280
    /// 否则 120，其余按 UTF-16 长度 44 字/行折行
    /// 28 + 行数×25。
    static func estBlockHeight(_ b: BlockState) -> Double {
        switch b.type {
        case "image", "gallery", "imgTextCard", "imageTextRow":
            return 280
        case "musicCard", "link-card", "embedCard":
            return 120
        case "attachment":
            return (b.node["image"] as? Bool) == true
                ? 280 : 120
        default:
            let len = plainText(of: b).utf16.count
            let lines = max(1.0, (Double(len) / 44.0)
                .rounded(.up))
            return 28 + lines * 25
        }
    }

    /// 无锚规范分界：在 [1, len-1] 取左右估高最接近点；
    /// 不足两块全归左栏。
    static func canonicalBoundary(
        blocks: [BlockState]) -> Int {
        if blocks.count < 2 { return blocks.count }
        let weights = blocks.map { estBlockHeight($0) }
        let total = weights.reduce(0, +)
        var running = 0.0
        var split = 1
        var best = Double.infinity
        for i in 1..<blocks.count {
            running += weights[i - 1]
            let diff = abs(total - running * 2)
            if diff < best { best = diff; split = i }
        }
        return split
    }

    /// 锚归一：right 名单第一个存活块为右栏起点；right
    /// 全灭时取 left 名单最后一个存活块之后；名单任一
    /// 缺失或两边无存活 id 返回 nil（视同无锚）。
    static func normalizeBoundary(
        blocks: [BlockState],
        layout: [String: Any]) -> Int? {
        guard let left = layout["left"] as? [String],
              let right = layout["right"] as? [String]
        else { return nil }
        let ids = blocks.map { $0.id }
        let positions = { (arr: [String]) in
            arr.compactMap { ids.firstIndex(of: $0) }
        }
        if let first = positions(right).min() { return first }
        if let last = positions(left).max() {
            return min(last + 1, blocks.count)
        }
        return nil
    }

    /// 当前有效分界：independent 走锚优先、flow 恒走
    /// 规范估高（Web 口径：flow 不读不写 layout 分界）。
    var columnBoundaryIndex: Int {
        if twoPaneIndependent, let l = layout,
           let b = Self.normalizeBoundary(
               blocks: blocks, layout: l) {
            return b
        }
        return Self.canonicalBoundary(blocks: blocks)
    }

    /// 独立双栏首次宽屏渲染且无有效锚时，按规范分界一
    /// 次性落锚写库（Web 落锚口径）；此后成员由锚决定。
    func captureAnchorIfNeeded() {
        if anchorCaptureDone { return }
        anchorCaptureDone = true
        guard twoPaneIndependent, blocks.count >= 2
        else { return }
        if let l = layout,
           Self.normalizeBoundary(
               blocks: blocks, layout: l) != nil {
            return
        }
        let b = Self.canonicalBoundary(blocks: blocks)
        let ids = blocks.map { $0.id }
        layout = ["version": 1, "mode": "independent",
                  "left": Array(ids[..<b]),
                  "right": Array(ids[b...])]
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT column anchor captured boundary=\(b)")
    }

    // ── MD 预览（E16 接线；解析走 core 同一解析器） ──
    /// 段落的 MD 分类（FFI md_classify；仅 paragraph
    /// 入判据，结果按文本缓存）。
    func mdKind(for block: BlockState) -> String {
        guard block.type == "paragraph" else { return "none" }
        if block.mdCacheText == block.text {
            return block.mdCacheKind
        }
        let kind = mdClassify(text: block.text)
        // 文本已变：先经失效单点作废旧解析树（清树与
        // 复位 done 同点，fix_md_cache_stale），再回
        // 填新文本与分类。漏复位 done 时，其后 mdBlocks
        // 会以「文本已对齐 + done 为真」命中空树。
        block.invalidateMdCache()
        block.mdCacheText = block.text
        block.mdCacheKind = kind
        return kind
    }

    /// 段落的 MD 解析树（FFI md_parse_json；元素为单键
    /// dict 或单元变体字符串如 "Divider"）。
    func mdBlocks(for block: BlockState) -> [Any] {
        if block.mdCacheText == block.text,
           block.mdCacheDone {
            return block.mdCacheBlocks
        }
        let json = mdParseJson(text: block.text)
        let arr = (try? JSONSerialization.jsonObject(
            with: Data(json.utf8))) as? [Any] ?? []
        block.mdCacheText = block.text
        block.mdCacheBlocks = arr
        block.mdCacheDone = true
        return arr
    }

    /// 点按预览回源码（Web 口径）：光标恒落源码末尾。
    func beginMdEdit(_ block: BlockState) {
        editingBlockId = block.id
        focusBlockId = block.id
        focusCaretEnd = true
    }

    /// 块级预览段判据（Web trail_judges 口径）。
    private func isBlockPreviewPara(_ b: BlockState)
        -> Bool {
        b.type == "paragraph" && mdKind(for: b) != "none"
            && mdIsBlockPreview(text: b.text)
    }

    /// 尾随空段物化（Web materialize_trails 口径）：块级
    /// 预览段（列表段除外）之后接文末/原子块/列表段/另
    /// 一预览段时，补一真实空段落（会落盘）；编辑中块
    /// 跳过、失焦时再补。重复调用幂等。
    func materializeMdTrails() {
        var inserted = 0
        var i = 0
        while i < blocks.count {
            let b = blocks[i]
            if isBlockPreviewPara(b),
               mdKind(for: b) != "list",
               editingBlockId != b.id {
                var need = false
                if i + 1 >= blocks.count {
                    need = true
                } else {
                    let next = blocks[i + 1]
                    need = BlockKind.trailAfterAtomic
                        .contains(next.type)
                        || next.isList
                        || mdKind(for: next) == "list"
                        || isBlockPreviewPara(next)
                }
                if need {
                    blocks.insert(BlockState(node: [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": "paragraph",
                        "children": [["text": ""]],
                    ]), at: i + 1)
                    inserted += 1
                    i += 2
                    continue
                }
            }
            i += 1
        }
        if inserted > 0 { scheduleSave() }
    }

    /// 双栏开关（Web toggle_twopane 口径）：翻转模式、
    /// 写用户级默认、按当前分界把 layout 重写为带新
    /// mode 的名单落库（切 flow 也写锚）。
    func toggleTwoPane() {
        pushHistory()
        let b = columnBoundaryIndex
        twoPaneIndependent.toggle()
        UserDefaults.standard.set(
            twoPaneIndependent,
            forKey: "editorIndependentScroll")
        let ids = blocks.map { $0.id }
        let bb = min(b, ids.count)
        layout = ["version": 1,
                  "mode": twoPaneIndependent
                      ? "independent" : "flow",
                  "left": Array(ids[..<bb]),
                  "right": Array(ids[bb...])]
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT twoPane toggled -> "
            + (twoPaneIndependent ? "independent" : "flow"))
    }

    private func snapshot() -> [String: Any] {
        ["title": title,
         "doc": blocks.map { $0.flushedNode() },
         "layout": layout ?? NSNull()]
    }

    /// 快照规范键（去重判等）：JSONSerialization
    /// sortedKeys 规范序列化——同一文档恒同键。
    /// 序列化失败（理论不可达，快照全为 JSON 形）
    /// 以唯一串兜底：去重永不误并、仅退化为不去重。
    private func snapshotKey(_ s: [String: Any])
        -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: s, options: [.sortedKeys]),
              let str = String(data: data,
                               encoding: .utf8)
        else { return UUID().uuidString }
        return str
    }

    /// UTF-16 偏移 → 字符口径偏移（与 pendingCaret-
    /// Offset 消费面 tv.text.count 同单位；越界钳
    /// 制、切代理对时回退为原值——BMP 文本恒等）。
    static func charOffset(text: String,
                           utf16Offset: Int) -> Int {
        let u = text.utf16
        let clamped = min(max(utf16Offset, 0), u.count)
        let ui = u.index(u.startIndex,
                         offsetBy: clamped)
        guard let si = String.Index(ui, within: text)
        else { return clamped }
        return text.distance(from: text.startIndex,
                             to: si)
    }

    /// 当前选区（历史条目附带，F-11）：编辑中块视
    /// 图的实时选区优先（字符口径）；其次焦点请求
    /// 在飞（其落点即选区，文末请求记 Int.max、恢
    /// 复时按目标单元长度钳制）；皆无则 nil（恢复
    /// 走兜底落点）。
    private func currentSel() -> UndoSel? {
        if let bid = editingBlockId,
           let tv = tvForBlock(bid) {
            let text = tv.text ?? ""
            let r = tv.selectedRange
            let loc = Self.charOffset(
                text: text, utf16Offset: r.location)
            let end = Self.charOffset(
                text: text,
                utf16Offset: r.location + r.length)
            return UndoSel(blockId: bid,
                           location: loc,
                           length: end - loc)
        }
        if let fid = focusBlockId {
            return UndoSel(
                blockId: fid,
                location: pendingCaretOffset
                    ?? (focusCaretEnd ? Int.max : 0),
                length: 0)
        }
        return nil
    }

    /// 操作边界记录（结构 op 与文本编辑会话开始的
    /// 全部调用点共用单点，签名沿旧 pushHistory、
    /// 调用点零改动）：变更前把当前状态记为返回
    /// 点——去重（幻影步根治）、上限 100、恒清重
    /// 做尾、断文本合并链。语义全在 UndoHistory-
    /// Core（E2/F-10）。
    func pushHistory() {
        let s = snapshot()
        _ = history.recordOpBoundary(
            payload: s, key: snapshotKey(s),
            sel: currentSel())
        syncHistoryFlags()
    }

    /// 文本变更前馈入（F-10 爆发合并）：should-
    /// ChangeTextIn 的普通文本放行点（代码块换行/
    /// 软换行/末尾兜底三处）在变更落模型前调——
    /// 600ms 内连续键入合并为一个返回点，撤销一
    /// 次回到爆发前（Web hist_push coalesce 同口
    /// 径）。快照取调用时刻的模型态（本键 runs 尚
    /// 未同步 = 变更前态），选区取被替换范围。非
    /// 空范围被非空文本替换（选区替换）恒起新返
    /// 回点、不被先行爆发链吞并（breaksBurst，
    /// EDT-14 步 5 定案，fix_undo_step5_selection
    /// .md）；纯删除（replacement 为空、含退格）
    /// 不置位、仍走爆发合并。
    func noteTextWillChange(blockId: String,
                            text: String,
                            range: NSRange,
                            replacement: String) {
        let loc = Self.charOffset(
            text: text, utf16Offset: range.location)
        let end = Self.charOffset(
            text: text,
            utf16Offset: range.location + range.length)
        // 快照经惰性工厂传入：窗内合并的逐键馈入
        // 不求值（不付全量快照 + 规范序列化成本）。
        let r = history.noteTextWillChange(
            entry: { let s = snapshot()
                     return (s, snapshotKey(s)) },
            sel: UndoSel(blockId: blockId,
                         location: loc,
                         length: end - loc),
            now: ProcessInfo.processInfo.systemUptime,
            breaksBurst: range.length > 0
                && !replacement.isEmpty)
        if r != .withinBurst { syncHistoryFlags() }
    }

    private func syncHistoryFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    private func applySnapshot(_ s: [String: Any]) {
        title = s["title"] as? String ?? title
        let doc = s["doc"] as? [[String: Any]] ?? []
        blocks = doc.map { BlockState(node: $0) }
        // 历史与 doc+layout 成对回退（Web 口径）：锚随
        // 快照恢复；模式开关状态本身不入历史。
        layout = s["layout"] as? [String: Any]
        scheduleSave()
    }

    /// 按 id 找文本单元（顶层文本块或列表项）：返
    /// 回 id + 字符数（选区恢复的钳制口径）。
    private func textUnit(
        id: String) -> (id: String, chars: Int)? {
        for b in blocks {
            if b.id == id, b.isText {
                return (b.id, b.text.count)
            }
            for item in b.itemStates
            where item.id == id {
                return (item.id, item.text.count)
            }
        }
        return nil
    }

    /// 第一个文本单元（恢复兜底落点，Web restore_
    /// focus 的 first_editable 同口径）。
    private func firstTextUnit()
        -> (id: String, chars: Int)? {
        for b in blocks {
            if b.isText { return (b.id, b.text.count) }
            if let item = b.itemStates.first {
                return (item.id, item.text.count)
            }
        }
        return nil
    }

    /// 撤销/重做后选区恢复（F-11）：优先回到条目
    /// 所附选区——块在恢复后文档中仍为文本单元
    /// 时，落点按该单元字符数钳制、选区长度随附
    /// （经 focusBlockId/pendingCaretOffset/
    /// pendingSelectionLength 既有消费面投递）；
    /// 块已不存在则落第一个文本单元首；全文无文
    /// 本单元则清焦点请求。返回判读串供 Diag。
    private func restoreSelection(_ sel: UndoSel?)
        -> String {
        if let sel, let unit = textUnit(id: sel.blockId) {
            let loc = min(max(sel.location, 0),
                          unit.chars)
            focusBlockId = unit.id
            pendingCaretOffset = loc
            pendingSelectionLength = min(
                max(sel.length, 0), unit.chars - loc)
            return "\(unit.id)@\(loc)"
                + "+\(pendingSelectionLength)"
        }
        if let first = firstTextUnit() {
            focusBlockId = first.id
            pendingCaretOffset = 0
            pendingSelectionLength = 0
            return "\(first.id)@0(fallback)"
        }
        focusBlockId = nil
        pendingCaretOffset = nil
        pendingSelectionLength = 0
        return "none"
    }

    /// 撤销漏斗单点（F-12）：菜单 / Cmd+Z / 三指
    /// 手势 / 标题字段 Cmd+Z 四入口只经此二函数。
    func undo() {
        let cur = snapshot()
        guard let target = history.performUndo(
            currentPayload: cur,
            currentKey: snapshotKey(cur),
            currentSel: currentSel()) else { return }
        applySnapshot(target.payload)
        let restored = restoreSelection(target.sel)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT undo 余栈 undo=\(history.undoDepth) "
            + "redo=\(history.redoDepth) "
            + "merged=\(history.mergedCount) "
            + "dedup=\(history.dedupedCount) "
            + "focus=\(restored)")
    }

    func redo() {
        let cur = snapshot()
        guard let target = history.performRedo(
            currentPayload: cur,
            currentKey: snapshotKey(cur),
            currentSel: currentSel()) else { return }
        applySnapshot(target.payload)
        let restored = restoreSelection(target.sel)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT redo 余栈 undo=\(history.undoDepth) "
            + "redo=\(history.redoDepth) "
            + "merged=\(history.mergedCount) "
            + "dedup=\(history.dedupedCount) "
            + "focus=\(restored)")
    }

    /// 正文字数（Web 口径：只计正文文本块，不含标题）。
    var wordCount: Int {
        blocks.filter { $0.isText }
            .reduce(0) { $0 + $1.text.count }
    }

    private func preparedItem() -> MemoItem {
        var it = item
        it.title = title
        it.blocks = blocks
        if let bg = bgColor {
            it.raw["bgColor"] = bg
        } else {
            it.raw.removeValue(forKey: "bgColor")
        }
        if let l = layout {
            it.raw["layout"] = l
        } else {
            it.raw.removeValue(forKey: "layout")
        }
        return it
    }

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.library.persist(self.preparedItem())
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6,
                                      execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        library.persist(preparedItem())
    }

    func setBgColor(_ hex: String?) {
        pushHistory()
        bgColor = hex
        scheduleSave()
    }

    // ── 块型转换单点（E3，Web apply_type +
    // clear_type_fields 等价） ──
    /// 旧类型字段清理（Web clear_type_fields 等
    /// 价）：摘 attrs 的 level/checked 两键。attrs
    /// 清空后整键摘除（不留空壳，与 Web 序列化省
    /// 略空 attrs 同果）。calloutType 不清——Web
    /// clear 同口径（变体字段转出保留、转回提示
    /// 时复活，两侧一致，审计定案登记）。
    private func clearTypeFields(_ n: inout [String: Any]) {
        guard var attrs = n["attrs"] as? [String: Any]
        else { return }
        attrs.removeValue(forKey: "level")
        attrs.removeValue(forKey: "checked")
        n["attrs"] = attrs.isEmpty ? nil : attrs
    }

    /// 块型转换单点（Web apply_type 口径）：块菜
    /// 单 setBlockType 与斜杠 applySlash 的 convert
    /// 两路径共用——先清旧类型字段、再按目标设新
    /// 字段（heading 设 level、todo 恒设 checked
    /// =false），根除 checked/level 残留落盘与
    /// 「转回待办勾选复活」（F-03）；待办重转两
    /// 路径 checked 口径随之收敛一致（m-02）。
    /// calloutType 不设：重转提示保留既有变体
    /// （M-04），新转入缺省呈现 note 与旧菜单路
    /// 径同果。children 不在此动（两路径各有口
    /// 径：菜单保留原 children、斜杠以当前 runs
    /// 重组后调用本点）；checked 镜像同步（转入
    /// todo 恒 false）；nodeVersion 由调用方 bump。
    func convertNodeType(_ b: BlockState, type: String,
                         level: Int = 2) {
        var n = b.node
        n["type"] = type
        clearTypeFields(&n)
        if type == "heading" || type == "todo" {
            var attrs = n["attrs"] as? [String: Any]
                ?? [:]
            if type == "heading" {
                attrs["level"] = level
            } else {
                attrs["checked"] = false
            }
            n["attrs"] = attrs
        }
        b.node = n
        if type == "todo" { b.checked = false }
    }

    /// 尾随空段补插（Web needsTrailingParagraph
    /// 口径）：转 todo/callout 后下一块不是现成
    /// 空段就补一段（M-03，菜单/斜杠顶层路径共
    /// 用；callout 与 todo 同臂系 Web op_convert
    /// 顶层口径，斜杠审计 S7）；焦点不动。现成
    /// 空段判定与 Web is_empty_para 同式
    /// （paragraph 且纯文本 trim 后为空）。
    private func ensureTrailingEmptyPara(
        after b: BlockState) {
        if let i = blocks.firstIndex(where: { $0 === b }),
           i + 1 < blocks.count,
           blocks[i + 1].type == "paragraph",
           blocks[i + 1].text.trimmingCharacters(
               in: .whitespaces).isEmpty {
            return
        }
        _ = trailingParagraph(after: b)
    }

    /// 有序列表起始号读取（Web list_start 口
    /// 径）：非 numbered 恒 1；字段缺失/非法
    /// （<1）读 1（存量无 start 按 1，读取不回写）。
    private func listStart(of list: BlockState) -> Int {
        guard list.type == "numbered-list" else { return 1 }
        let attrs = list.node["attrs"] as? [String: Any]
        let s = attrs?["start"] as? Int ?? 1
        return s >= 1 ? s : 1
    }

    /// 有序列表起始号写入（Web set_list_start
    /// 口径）：仅 numbered 生效；start ≤ 1 删字
    /// 段（常态不落冗余字节）。
    private func setListStart(_ list: BlockState,
                              _ start: Int) {
        guard list.type == "numbered-list" else { return }
        var n = list.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        if start <= 1 {
            attrs.removeValue(forKey: "start")
        } else {
            attrs["start"] = start
        }
        n["attrs"] = attrs.isEmpty ? nil : attrs
        list.node = n
    }

    /// 列表头部摘除 removed 项后 start 递增
    /// （Web shift_list_start 口径）：存续项显示
    /// 号不变（F-05）。可见性为内部级：跨块选区
    /// replaceRange（MomentXSelBridge.swift 的
    /// EditorModel 扩展）共用此单点，不另写一份。
    func shiftListStart(_ list: BlockState,
                        by removed: Int) {
        guard removed > 0 else { return }
        setListStart(list, listStart(of: list) + removed)
    }

    /// 待办勾选切换（具名入口，U4a 抽取）：勾选钮
    /// 与自检驱动共用同一体——压历史、翻转、回写
    /// node attrs、版本自增、排保存，五步恒同序。
    func toggleTodoChecked(_ b: BlockState) {
        pushHistory()
        b.checked.toggle()
        var n = b.node
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        attrs["checked"] = b.checked
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
    }

    func setBlockType(_ b: BlockState, type: String,
                      level: Int = 2) {
        pushHistory()
        convertNodeType(b, type: type, level: level)
        if type == "todo" || type == "callout" {
            ensureTrailingEmptyPara(after: b)
        }
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT convert \(b.id) -> \(type)"
            + (type == "heading" ? " level=\(level)" : ""))
    }

    /// 智能前缀命中（F-02，Web ops.rs smart_prefix_
    /// match 逐条镜像）：只看首行（多行文本首行之外
    /// 的内容在 Web 转换时一并丢弃、同口径）；捕获
    /// 正文为 trim 后文本（rest 仅空白时正文为空串
    /// 仍命中，与 Web 同式）。
    private enum SmartPrefixHit {
        case heading(Int, String)
        case quote(String)
        case todo(String)
        case divider
    }

    private static func smartPrefixMatch(
        _ raw: String) -> SmartPrefixHit? {
        if raw.isEmpty { return nil }
        let firstLine = raw.prefix(while: { $0 != "\n" })
        // ### / ## / # + 字面空格 + 至少一字符。
        for (prefix, level) in [("### ", 3), ("## ", 2),
                                ("# ", 1)] {
            if firstLine.hasPrefix(prefix) {
                let rest = firstLine.dropFirst(prefix.count)
                if !rest.isEmpty {
                    return .heading(level, String(rest)
                        .trimmingCharacters(
                            in: .whitespaces))
                }
            }
        }
        // > + 至少一字符；> [!TYPE] 是标注源段、不
        // 转引用（与 md_classify 的 Callout 同界）。
        if firstLine.hasPrefix(">") {
            let rest = firstLine.dropFirst()
            if !rest.isEmpty {
                let t = rest.drop(while: { c in
                    c.unicodeScalars.allSatisfy({
                        CharacterSet.whitespaces
                            .contains($0)
                    })
                })
                var callout = false
                if t.hasPrefix("[!") {
                    let after = t.dropFirst(2)
                    if let c = after.first,
                       !c.unicodeScalars.allSatisfy({
                           CharacterSet.whitespaces
                               .contains($0)
                       }) {
                        callout = true
                    }
                }
                if !callout {
                    return .quote(String(rest)
                        .trimmingCharacters(
                            in: .whitespaces))
                }
            }
        }
        // [ ] / [] + 字面空格 + 至少一字符 → 待办。
        for prefix in ["[ ] ", "[] "] {
            if firstLine.hasPrefix(prefix) {
                let rest = firstLine.dropFirst(prefix.count)
                if !rest.isEmpty {
                    return .todo(String(rest)
                        .trimmingCharacters(
                            in: .whitespaces))
                }
            }
        }
        // 分隔线：全文恰为 ---（不 trim、全串相等）。
        if raw == "---" { return .divider }
        return nil
    }

    /// 智能前缀尾扫（F-02，Web apply_smart_prefix
    /// 口径）：扫全 doc 顶层段落（文档序），首个命
    /// 中者转块型、每次只转一处；转换形态与斜杠转
    /// 换同构（同 id、单文本子节点、类型字段走转
    /// 换单点 convertNodeType 先清后设、正文为捕
    /// 获的纯文本——行内格式随 Web 同口径不保
    /// 留）；焦点落新块文末。divider 只原地替换、
    /// 不补尾随段，焦点落 divider 本身（caret 0）。
    /// 斜杠面板/链接表单打开时跳过（Web showSlash
    /// 守卫）。调用点与 Web 文本类消息尾一一对应：
    /// didChange（inputSync）、insertLines（paste
    /// Text）、splitBlock（split）、merge 两路
    /// （merge）；组字期由 didChange 守卫天然不到
    /// 此处。
    func applySmartPrefixIfNeeded() {
        guard slashBlockId == nil,
              linkFormBlockId == nil else { return }
        for b in blocks where b.type == "paragraph" {
            guard let hit = Self.smartPrefixMatch(b.text)
            else { continue }
            pushHistory()
            switch hit {
            case .divider:
                b.node = ["id": b.id, "type": "divider"]
                b.nodeVersion += 1
                if editingBlockId == b.id {
                    editingBlockId = nil
                }
                focusBlockId = b.id
                focusCaretEnd = false
                pendingCaretOffset = 0
                DiagLog.shared.log(.info,
                    "EDIT smart prefix -> divider "
                    + "\(b.id)")
            case .heading(let level, let text):
                convertSmartPrefix(b, type: "heading",
                                   level: level, text: text)
                DiagLog.shared.log(.info,
                    "EDIT smart prefix -> heading"
                    + "\(level) \(b.id)")
            case .quote(let text):
                convertSmartPrefix(b, type: "quote",
                                   text: text)
                DiagLog.shared.log(.info,
                    "EDIT smart prefix -> quote \(b.id)")
            case .todo(let text):
                convertSmartPrefix(b, type: "todo",
                                   text: text)
                DiagLog.shared.log(.info,
                    "EDIT smart prefix -> todo \(b.id)")
            }
            scheduleSave()
            return
        }
    }

    /// 智能前缀的文本类转换落点（与 applySlash 的
    /// convert 同形：children 以新 runs 重组后走转
    /// 换单点，焦点落转换后文本末尾）。
    private func convertSmartPrefix(_ b: BlockState,
                                    type: String,
                                    level: Int = 2,
                                    text: String) {
        b.runs = text.isEmpty ? [] : [["text": text]]
        var n = b.node
        n["children"] = BlockState.childrenFrom(
            runs: b.runs)
        b.node = n
        convertNodeType(b, type: type, level: level)
        b.text = text
        b.nodeVersion += 1
        focusBlockId = b.id
        focusCaretEnd = false
        pendingCaretOffset = text.count
    }

    func addImageBlock(fileId: String) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "image",
            "attrs": ["fileId": fileId],
            "children": [],
        ])
        blocks.append(b)
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT add image block \(fileId)")
    }

    /// 视频块新建（F-15，2026-11-27 裁定原生增强；
    /// Web 无插入路、仅存量呈现）：节点形与 image 块
    /// 同位（attrs.fileId 为规范位——Web blocks.rs 的
    /// video 分支正是按 file_id 渲染 BlobMedia、原生
    /// VideoBlockView 亦按 block.fileId 取数），入块
    /// 路由在附件/选片两处按 UTType.movie 分流。
    func addVideoBlock(fileId: String) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "video",
            "attrs": ["fileId": fileId],
            "children": [],
        ])
        blocks.append(b)
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT add video block \(fileId)")
    }

    /// 粘贴图片成块（E17）：存附件后在当前块后插图片
    /// 块；图后非文本块则补尾随空段并落焦（原子块收尾
    /// 口径），是文本块则落焦其首。
    func insertPastedImage(block: BlockState, data: Data) {
        let fid = "att-" + UUID().uuidString
            .prefix(12).lowercased()
        // 写失败不成块：不留引用空附件的死块。
        guard library.putAttachment(fid, data) else {
            DiagLog.shared.log(.error,
                "粘贴图片未成块（附件写入失败）fid=\(fid)")
            return
        }
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "image",
            "attrs": ["fileId": fid],
            "children": [],
        ])
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            blocks.insert(b, at: i + 1)
            if i + 2 < blocks.count, blocks[i + 2].isText {
                focusBlockId = blocks[i + 2].id
                focusCaretEnd = false
            } else {
                let p = trailingParagraph(after: b)
                focusBlockId = p.id
                focusCaretEnd = false
            }
        } else {
            blocks.append(b)
        }
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT paste image -> block \(fid)")
    }

    func addAttachmentBlock(fileId: String, name: String,
                            size: Int) {
        pushHistory()
        let b = BlockState(node: [
            "id": "b-" + UUID().uuidString.prefix(8).lowercased(),
            "type": "attachment",
            "attrs": ["fileId": fileId, "name": name,
                      "size": size],
            "children": [],
        ])
        blocks.append(b)
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT attach \(fileId) \(name)")
    }

    func deleteBlock(_ b: BlockState) {
        pushHistory()
        if selectedBlockId == b.id {
            selectedBlockId = nil
        }
        blocks.removeAll { $0.id == b.id }
        if blocks.isEmpty {
            blocks.append(BlockState(
                node: Self.emptyParagraphNode()))
        }
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT delete block \(b.id) type=\(b.type)")
    }

    /// 回车拆块（Web 口径）：当前块留 before，新块承
    /// after 并聚焦（光标落新块首）。
    func splitBlock(_ b: BlockState,
                    before: NSAttributedString,
                    after: NSAttributedString) {
        pushHistory()
        let base = Marks.baseFont(for: b)
        b.runs = Marks.runs(from: before, base: base)
        b.text = before.string
        b.nodeVersion += 1
        var node: [String: Any] = [
            "id": "b-" + UUID().uuidString.prefix(8)
                .lowercased(),
            "type": b.type == "heading" ? "paragraph" : b.type,
            "children": [["text": after.string]],
        ]
        if b.type == "todo" {
            node["attrs"] = ["checked": false]
        }
        let nb = BlockState(node: node)
        nb.runs = Marks.runs(from: after, base: base)
        nb.text = after.string
        if let i = blocks.firstIndex(where: { $0.id == b.id }) {
            blocks.insert(nb, at: i + 1)
        } else {
            blocks.append(nb)
        }
        focusBlockId = nb.id
        focusCaretEnd = false
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT split \(b.type) \(b.id) -> \(nb.id)")
        // 智能前缀尾扫（F-02，Web split 消息尾同位）。
        applySmartPrefixIfNeeded()
    }

    /// T-4：空待办/空引用回车——自身转段落退出该类
    /// 型（摘 todo 的 checked 属性），不拆块、光标留
    /// 原块。非空时不走此路（回车仍拆块产同型新块）。
    func exitEmptyBlock(_ b: BlockState) {
        pushHistory()
        var n = b.node
        n["type"] = "paragraph"
        n.removeValue(forKey: "attrs")
        b.node = n
        b.nodeVersion += 1
        focusBlockId = b.id
        focusCaretEnd = true
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT split-exit-styled \(b.id)")
    }

    /// 并块后光标落点（字符偏移），BlockTextView 消费。
    var pendingCaretOffset: Int?
    // E2/F-11：待投递选区长度（字符口径）——撤销/
    // 重做恢复非零选区时与 pendingCaretOffset 配
    // 对投递（updateUIView 两支消费后随落点一并
    // 异步清零），其余路径恒 0。
    var pendingSelectionLength = 0

    /// 向前找最近的文本块（跳过原子块，T-11 口径）。
    private func nearestTextBlock(before i: Int) -> BlockState? {
        var j = i - 1
        while j >= 0 {
            if blocks[j].isText { return blocks[j] }
            j -= 1
        }
        return nil
    }

    /// 段首退格并块（Web 口径）：并入上一文本块，光标
    /// 落接合处；当前块为空时删块并向前跳过原子块落
    /// 最近文本块末尾（T-11，无目标则保留空块）；prev
    /// 为列表块时并入其末项（T-13）。结构守卫成员
    /// （isStructuralAtomic，卡片机制）两向例外：自身
    /// 为成员时不并入前块、prev 为成员时落 F-08 选
    /// 中支（impl_card_guard_unify；Web 文本流口径的
    /// 有意偏离，仅限成员集）。
    func mergeBlockBackward(_ b: BlockState) {
        guard let i = blocks.firstIndex(
            where: { $0.id == b.id }), i > 0 else { return }
        let prev = blocks[i - 1]
        if b.text.isEmpty {
            guard let target = nearestTextBlock(before: i)
            else {
                // 无更早文本块：保留空块、无动作
                // （Web 同口径，Diag 对齐其 kept 行）。
                DiagLog.shared.log(.info,
                    "EDIT merge empty \(b.id) kept "
                    + "(only atomics before)")
                return
            }
            pushHistory()
            blocks.remove(at: i)
            focusBlockId = target.id
            focusCaretEnd = true
            DiagLog.shared.log(.info,
                "EDIT merge empty \(b.id) -> \(target.id)")
        } else if b.isStructuralAtomic {
            // 结构守卫·自身支（卡片机制，
            // impl_card_guard_unify）：成员（代码块）
            // 段首退格不并入前块——并入即块身份与字
            // 面内容一并溶解（卡片无文本、天然无此
            // 路）。按键已在 shouldChange 吞掉，此处
            // 只落 Diag、不动数据，与 F-08 原子支同
            // 为「键盘无结构动作」收口。空成员自删走
            // 上方空支（无内容可失，不在守卫面内）。
            DiagLog.shared.log(.info,
                "EDIT merge backspace guarded self "
                + "\(b.id) kept (no merge)")
        } else if prev.isText && !prev.isStructuralAtomic {
            pushHistory()
            let junction = prev.text.count
            prev.runs = prev.runs + b.runs
            prev.text = prev.text + b.text
            prev.nodeVersion += 1
            blocks.remove(at: i)
            focusBlockId = prev.id
            focusCaretEnd = false
            pendingCaretOffset = junction
            DiagLog.shared.log(.info,
                "EDIT merge \(b.id) -> \(prev.id) "
                + "at \(junction)")
        } else if prev.type == "bulleted-list"
            || prev.type == "numbered-list",
            let last = prev.itemStates.last {
            // T-13：段落并入列表末项，光标落接合处。
            pushHistory()
            let junction = last.text.count
            last.runs = last.runs + b.runs
            last.text = last.text + b.text
            last.nodeVersion += 1
            prev.nodeVersion += 1
            blocks.remove(at: i)
            focusBlockId = last.id
            focusCaretEnd = false
            pendingCaretOffset = junction
            DiagLog.shared.log(.info,
                "EDIT merge \(b.id) -> list-item "
                + "\(last.id)")
        } else {
            // F-08：非空块段首退格撞原子前驱——Web
            // op_merge 原子支口径：不删原子块、不并
            // 文本，只把原子块带入选中态（sel_block
            // 同位），两块与文本全保留；键盘永不删
            // 非文本块（删除走卡菜单明路）。此前三
            // 分支全不命中、按键已被 shouldChange
            // 吞掉，是无效果、无 Diag 的死键。
            selectedBlockId = prev.id
            DiagLog.shared.log(.info,
                "EDIT merge backspace before atomic "
                + "\(prev.id) selected (kept)")
        }
        scheduleSave()
        // 智能前缀尾扫（F-02，Web merge 消息尾同位）。
        applySmartPrefixIfNeeded()
    }

    /// 向后找最近的文本块（跳过原子块与列表，
    /// nearestTextBlock(before:) 的镜像）。
    private func nearestTextBlock(after i: Int)
        -> BlockState? {
        var j = i + 1
        while j < blocks.count {
            if blocks[j].isText { return blocks[j] }
            j += 1
        }
        return nil
    }

    /// 块末前向删除并块（B-05，Web op_merge_forward
    /// 同口径）：与段首退格严格对称——内容恒并入
    /// 较早的存活块、光标落接合处。当前块为空时删
    /// 块、向后跳过原子块落最近文本块块首（无目标
    /// 保留空块）；下一块为列表时其首项并入当前
    /// 块；下一块为原子块时不删、只带入选中态。结
    /// 构守卫成员两向例外与退格镜像：自身为成员时
    /// 不吸收后块、next 为成员时落选中支
    /// （impl_card_guard_unify）。
    func mergeBlockForward(_ b: BlockState) {
        guard let i = blocks.firstIndex(
            where: { $0.id == b.id }) else { return }
        if b.text.isEmpty {
            guard let target = nearestTextBlock(
                after: i) else {
                // 无更晚文本块：保留空块、无动作
                // （退格空支镜像，Diag 对齐其 kept
                // 行）。
                DiagLog.shared.log(.info,
                    "EDIT merge fwd empty \(b.id) kept "
                    + "(only atomics after)")
                return
            }
            pushHistory()
            blocks.remove(at: i)
            focusBlockId = target.id
            focusCaretEnd = false
            pendingCaretOffset = 0
            DiagLog.shared.log(.info,
                "EDIT merge fwd empty \(b.id) "
                + "-> \(target.id)")
        } else if i < blocks.count - 1 {
            let next = blocks[i + 1]
            if b.isStructuralAtomic {
                // 结构守卫·自身支（段首退格自守卫的
                // 镜像）：成员（代码块）块末前向删除
                // 不吸收后块入内，只落 Diag、不动数据。
                DiagLog.shared.log(.info,
                    "EDIT merge fwd guarded self "
                    + "\(b.id) kept (no merge)")
            } else if next.isText && !next.isStructuralAtomic {
                pushHistory()
                let junction = b.text.count
                b.runs = b.runs + next.runs
                b.text = b.text + next.text
                b.nodeVersion += 1
                blocks.remove(at: i + 1)
                focusBlockId = b.id
                focusCaretEnd = false
                pendingCaretOffset = junction
                DiagLog.shared.log(.info,
                    "EDIT merge fwd \(next.id) "
                    + "-> \(b.id) at \(junction)")
            } else if next.isList,
                      let first = next.itemStates.first {
                // T-13 镜像：下一列表首项并入当前
                // 块，存续首项原号不变 → start +1；
                // 表空删表。
                pushHistory()
                let junction = b.text.count
                b.runs = b.runs + first.runs
                b.text = b.text + first.text
                b.nodeVersion += 1
                next.itemStates.remove(at: 0)
                if next.itemStates.isEmpty {
                    blocks.remove(at: i + 1)
                } else {
                    shiftListStart(next, by: 1)
                }
                next.nodeVersion += 1
                focusBlockId = b.id
                focusCaretEnd = false
                pendingCaretOffset = junction
                DiagLog.shared.log(.info,
                    "EDIT merge fwd list-item "
                    + "\(first.id) -> \(b.id) "
                    + "at \(junction)")
            } else {
                // 原子后继（F-08 镜像）：不删原子
                // 块、不并文本，只带入选中态，两块
                // 全保留；删卡走卡菜单明路。
                selectedBlockId = next.id
                DiagLog.shared.log(.info,
                    "EDIT merge fwd before atomic "
                    + "\(next.id) selected (kept)")
            }
        } else {
            // 末块块末：无下一块、无动作。
            return
        }
        scheduleSave()
        // 智能前缀尾扫（F-02，merge 消息尾同位）。
        applySmartPrefixIfNeeded()
    }

    /// 前向删除并块的按键面入口：按 blockId 定位
    /// 编辑单元——顶层文本块走 mergeBlockForward、
    /// 列表项（含嵌套）走 mergeListItemForward；
    /// 定位不到放行原生（理论不可达）。
    func mergeForwardFromKey(blockId: String) -> Bool {
        if let b = blocks.first(
            where: { $0.id == blockId }), b.isText {
            mergeBlockForward(b)
            return true
        }
        for list in blocks where list.isList {
            if let hit = findItem(blockId, in: list) {
                mergeListItemForward(list: hit.list,
                                     item: hit.item)
                return true
            }
        }
        return false
    }

    /// 在列表（含嵌套子表）内按 id 找列表项。
    private func findItem(
        _ id: String, in list: BlockState
    ) -> (list: BlockState, item: BlockState)? {
        for item in list.itemStates {
            if item.id == id { return (list, item) }
            if let nested = item.nestedList,
               let hit = findItem(id, in: nested) {
                return hit
            }
        }
        return nil
    }

    /// 多行文本插入（回车于列表项 / 粘贴多行共用，E17）：
    /// 当前块保留 before+首行，其余行逐行成新块（列表项
    /// 或同类文本块，heading 降段落），末行拼 after。
    func insertLines(_ b: BlockState,
                     listParent: BlockState?,
                     before: NSAttributedString,
                     lines: [String],
                     after: NSAttributedString) {
        guard !lines.isEmpty else { return }
        pushHistory()
        let base = Marks.baseFont(for: b)
        func plainRuns(_ s: String) -> [[String: Any]] {
            s.isEmpty ? [] : [["text": s]]
        }
        let beforeRuns = Marks.runs(from: before, base: base)
        let afterRuns = Marks.runs(from: after, base: base)
        b.runs = beforeRuns + plainRuns(lines[0])
        b.text = before.string + lines[0]
        b.nodeVersion += 1
        var lastBlock = b
        if lines.count > 1 {
            for k in 1..<lines.count {
                let isLast = k == lines.count - 1
                let segRuns = plainRuns(lines[k])
                    + (isLast ? afterRuns : [])
                let segText = lines[k]
                    + (isLast ? after.string : "")
                if let list = listParent {
                    let node: [String: Any] = [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": "list-item",
                        "children": [["text": segText]],
                    ]
                    let nb = BlockState(node: node)
                    nb.runs = segRuns
                    nb.text = segText
                    if let i = list.itemStates.firstIndex(
                        where: { $0 === lastBlock }) {
                        list.itemStates.insert(nb, at: i + 1)
                    } else {
                        list.itemStates.append(nb)
                    }
                    lastBlock = nb
                } else {
                    var node: [String: Any] = [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": b.type == "heading"
                            ? "paragraph" : b.type,
                        "children": [["text": segText]],
                    ]
                    if b.type == "todo" {
                        node["attrs"] = ["checked": false]
                    }
                    let nb = BlockState(node: node)
                    nb.runs = segRuns
                    nb.text = segText
                    if let i = blocks.firstIndex(
                        where: { $0 === lastBlock }) {
                        blocks.insert(nb, at: i + 1)
                    } else {
                        blocks.append(nb)
                    }
                    lastBlock = nb
                }
            }
        } else {
            b.runs = b.runs + afterRuns
            b.text = b.text + after.string
            b.nodeVersion += 1
        }
        listParent?.nodeVersion += 1
        focusBlockId = lastBlock.id
        focusCaretEnd = lines.count == 1
        if lines.count > 1 {
            pendingCaretOffset = nil
            focusCaretEnd = false
            // 光标落末块 = 末行文本长度（不含 after 时为行末）
            pendingCaretOffset = lines[lines.count - 1].count
        }
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT insert lines \(lines.count) into \(b.id)")
        // 智能前缀尾扫（F-02，Web pasteText 消息尾
        // 同位：「# 标题行\n正文」首块成标题）。
        applySmartPrefixIfNeeded()
    }

    /// 空项回车退出列表（Web 口径）：该项转空段落落到
    /// 列表后，其后子项自成新列表（列表被劈开）。
    func exitListItem(list: BlockState, item: BlockState) {
        guard let idx = list.itemStates.firstIndex(
            where: { $0 === item }) else { return }
        pushHistory()
        let trailing = Array(
            list.itemStates.dropFirst(idx + 1))
        list.itemStates.removeSubrange(idx...)
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let li = blocks.firstIndex(where: { $0 === list }) {
            if list.itemStates.isEmpty && trailing.isEmpty {
                blocks[li] = p
            } else if list.itemStates.isEmpty {
                blocks[li] = p
                let nl = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": list.type,
                    "children": [],
                ])
                nl.itemStates = trailing
                // 尾表 start 按首项号传递（F-05，
                // Web op_split 同式：原 start +
                // idx + 1，被退出项占一号）。
                setListStart(nl, listStart(of: list)
                             + idx + 1)
                blocks.insert(nl, at: li + 1)
            } else {
                blocks.insert(p, at: li + 1)
                if !trailing.isEmpty {
                    let nl = BlockState(node: [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": list.type,
                        "children": [],
                    ])
                    nl.itemStates = trailing
                    setListStart(nl, listStart(of: list)
                                 + idx + 1)
                    blocks.insert(nl, at: li + 2)
                }
            }
        }
        list.nodeVersion += 1
        focusBlockId = p.id
        focusCaretEnd = false
        scheduleSave()
    }

    // ── 斜杠菜单（E14） ────────────────────────────
    @Published var slashBlockId: String?
    @Published var slashQuery: String = ""
    /// 键盘选中行（命令行序索引，Web .slash-row.sel
    /// 的单源态）：查询变更/新开面板归零（首行选中，
    /// Web render sel 首行口径）。
    @Published var slashSel: Int = 0
    /// 斜杠面板横向锚（J2-F18，Web render.rs 的
    /// anchor_x 口径）：触发块 UITextView 光标矩形
    /// 换算到窗口的 X，由 textViewDidChange 在调
    /// updateSlash 时同步写入；面板 left 按 Web 公
    /// 式以此为锚（编辑器整屏呈现，窗口 X 与面板层
    /// 坐标同源）。
    @Published var slashAnchorX: CGFloat = 0
    /// 斜杠面板纵向锚（B-03）：触发行（光标行）窗
    /// 口上下缘 + 绑定块 id，与横向锚同通道写入
    /// （窗口 Y 与面板层同源，沿 slashAnchorX 既
    /// 有口径）。面板纵向定顶改吃光标行（Web 以
    /// 触发点 getBoundingClientRect 定锚）；旧按
    /// 整块底定顶，长块中段触发时面板脱锚至块尾。
    /// 锚缺失/异块时 slashLayer 逐字回退块底公式。
    @Published var slashAnchorTopY: CGFloat = 0
    @Published var slashAnchorBottomY: CGFloat = 0
    var slashAnchorBlockId: String?
    @Published var linkFormBlockId: String?

    /// 方向键移选（Web 桥 moveSel：环绕）。
    func slashMoveSel(_ dir: Int) {
        let n = SlashCmds.rowCommands(slashQuery).count
        guard n > 0 else { return }
        slashSel = ((slashSel + dir) % n + n) % n
    }

    /// Home/End 跳首/尾（Web 桥 selEdge）。
    func slashSelEdge(last: Bool) {
        let n = SlashCmds.rowCommands(slashQuery).count
        guard n > 0 else { return }
        slashSel = last ? n - 1 : 0
    }

    /// 回车执行选中行（Web 桥 Enter 分支）：按
    /// slashSel 取行序命令走 applySlash 单路（link
    /// 在其内分流表单、行内命令在其内分流包裹）。
    func slashApplySelected() {
        let cmds = SlashCmds.rowCommands(slashQuery)
        guard !cmds.isEmpty else { return }
        let i = min(max(slashSel, 0), cmds.count - 1)
        applySlash(cmds[i].act)
    }

    // ── 跨块方向键导航（Web crossBlockArrow） ──────
    /// 文本视图弱注册表（block.id → EditorTextView）：
    /// 方向键落焦须直接对目标视图 becomeFirstRes-
    /// ponder + 定选区（手势/按键内同步，不走 focus-
    /// BlockId 的滚动管线——那条只定块首）。
    private final class WeakTVBox {
        weak var tv: EditorTextView?
    }
    private var tvRegistry: [String: WeakTVBox] = [:]

    func registerTV(_ tv: EditorTextView, blockId: String) {
        let box = WeakTVBox()
        box.tv = tv
        tvRegistry[blockId] = box
    }

    func unregisterTV(_ tv: EditorTextView) {
        tvRegistry = tvRegistry.filter {
            $0.value.tv != nil && $0.value.tv !== tv
        }
    }

    /// 可见性为内部级：跨块选区二期扩展的几何量
    /// 测（MomentXSelBridge.swift 的 EditorModel
    /// 扩展）共用注册表/行盒/hit-test 三单点，不
    /// 另写一份（shiftListStart 跨文件共用先例）。
    func tvForBlock(_ id: String) -> EditorTextView? {
        tvRegistry[id]?.tv
    }

    /// 拾起收敛选区（0.9.49，Web pickup 的
    /// removeAllRanges 对应动作）：按压引擎与
    /// UITextView 选区长按现并行放开，文本块被拾起
    /// 的瞬间，本块文本视图可能已同步起了选区（放
    /// 大镜/选区柄）——拾起即清选区；本视图若因此
    /// 次长按持了焦点则一并辞焦（武装口径下本块不
    /// 是正在编辑的块，辞焦不伤编辑态）。返回是否
    /// 实际收敛（供行侧留痕）。非文本块无注册视图，
    /// 直接返回 false。
    func convergeSelectionOnPickup(blockId: String)
        -> Bool {
        guard let tv = tvForBlock(blockId) else {
            return false
        }
        var acted = false
        if tv.selectedTextRange != nil {
            tv.selectedTextRange = nil
            acted = true
        }
        if tv.isFirstResponder {
            tv.resignFirstResponder()
            acted = true
        }
        return acted
    }

    /// 可编辑文本单元（Web 扁平链 .text-block,
    /// .callout-edit, .li-text 的 DOM 序）：顶层文本
    /// 块（isText 含 quote/callout）直入；列表递归
    /// itemStates + nestedList（父项先于其嵌套项）。
    struct NavUnit {
        var block: BlockState
        var listParent: BlockState?
    }

    func textUnits() -> [NavUnit] {
        var out: [NavUnit] = []
        func walkList(_ list: BlockState) {
            for item in list.itemStates {
                out.append(NavUnit(block: item,
                                   listParent: list))
                if let nested = item.nestedList {
                    walkList(nested)
                }
            }
        }
        for b in blocks {
            if b.isText {
                out.append(NavUnit(block: b, listParent: nil))
            } else if b.isList {
                walkList(b)
            }
        }
        return out
    }

    /// 目标列会话（Web arrowGoalX/arrowManual）：连
    /// 续 ↑↓ 维持起始列的窗口 X；会话内已手动移过
    /// 行后块内续移也走手动（原生默认列记忆口径不
    /// 同）。散场：非 ↑↓ 键、文本变更、点按。
    private var arrowGoalX: CGFloat?
    private var arrowManual = false

    func resetArrowGoal() {
        arrowGoalX = nil
        arrowManual = false
    }

    /// 硬件键盘按键分发（EditorTextView.pressesBegan
    /// 钩调）：true = 已消费（默认处理不发生）。分
    /// 发序（Web keydown 口径）：斜杠面板开时 ↑↓/
    /// Enter/Home/End 归面板（Esc 不在此消费、归页
    /// 眉既有 Esc 链）；方向键无修饰、非组字、选区
    /// 折叠才进 crossBlockArrow；其余放行（非方向
    /// 键与 ←/→ 散目标列会话）。
    func handleKey(_ tv: EditorTextView, blockId: String,
                   press: UIPress) -> Bool {
        guard let key = press.key else { return false }
        let code = key.keyCode
        // F-09 一期跨块选区命令面（Web keydown 同序、
        // 置撤销拦截之前）：xsel 在位时 Cmd+A 重选全
        // 文、Cmd+C/X 走选区文本（剪贴板写在本面、
        // 模型层不碰）；Cmd+Z/Y 与其余 Cmd 组合先清
        // 选再放行（Web「Ctrl/Cmd 按下清 xsel」口径，
        // 撤销由下方 E2 支照常接管）。xsel 不在位时
        // Cmd+A 建立全文选区（源码态块内不触发，
        // Web !isSrcBlock 同口径）。
        if key.modifierFlags.contains(.command) {
            if xsel != nil {
                switch code {
                case .keyboardA:
                    selectAllXSel()
                    return true
                case .keyboardC:
                    if let t = xselClipboardText(),
                       !t.isEmpty {
                        UIPasteboard.general.string = t
                    }
                    return true
                case .keyboardX:
                    if let t = cutXSelText(), !t.isEmpty {
                        UIPasteboard.general.string = t
                    }
                    return true
                default:
                    clearXSel()
                }
            } else if code == .keyboardA,
                      !isXSelSourceBlock(blockId) {
                selectAllXSel()
                return true
            }
        }
        // E2/F-12 撤销快捷键单轨：Cmd+Z / Cmd+Shift+Z
        // / Cmd+Y 在此拦截消费（pressesBegan 不再上
        // 抛 super），与菜单、三指手势同走 undo()/
        // redo() 漏斗；正文视图 undoManager 已钉
        // nil（EditorTextView），系统撤销轨不介入、
        // 不双撤。
        if key.modifierFlags.contains(.command) {
            if code == .keyboardZ {
                if key.modifierFlags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return true
            }
            if code == .keyboardY {
                redo()
                return true
            }
        }
        if slashBlockId != nil {
            switch code {
            case .keyboardUpArrow:
                slashMoveSel(-1)
                return true
            case .keyboardDownArrow:
                slashMoveSel(1)
                return true
            case .keyboardReturnOrEnter, .keypadEnter:
                slashApplySelected()
                return true
            case .keyboardHome:
                slashSelEdge(last: false)
                return true
            case .keyboardEnd:
                slashSelEdge(last: true)
                return true
            default:
                break
            }
        }
        // F-09 一期：xsel 在位时的编辑键接管（Web
        // keydown xsel 支同序）——删除/回车/覆打/
        // Esc/无修饰方向收拢；组字中不消费（组字开
        // 始已收拢、marked 在位本面整体让路）。Shift
        // +方向 = 二期端点扩展（桥接层 xselExtend，
        // Web 同支）：接管成立即消费；未命中（焦点
        // 视图不可测）按 Web 未命中口径收拢到焦点
        // 端后放行原生块内扩展。其余功能键收拢后
        // 放行（Web else 支）。
        if xsel != nil, tv.markedTextRange == nil {
            let xmods = key.modifierFlags.intersection(
                [.shift, .alternate, .control, .command])
            switch code {
            case .keyboardDeleteOrBackspace,
                 .keyboardDeleteForward:
                if xmods.isEmpty {
                    resetArrowGoal()
                    replaceXSel(text: "", enter: false)
                    return true
                }
            case .keyboardReturnOrEnter, .keypadEnter:
                if xmods.isEmpty || xmods == [.shift] {
                    resetArrowGoal()
                    replaceXSel(text: "", enter: true)
                    return true
                }
            case .keyboardEscape:
                collapseXSel()
                return true
            case .keyboardLeftArrow, .keyboardUpArrow:
                if xmods.isEmpty {
                    collapseXSel(toOrderedStart: true)
                    return true
                }
                if xmods == [.shift] {
                    resetArrowGoal()
                    if xselExtend(
                        dir: code == .keyboardLeftArrow
                            ? .left : .up) {
                        return true
                    }
                    collapseXSel()
                    return false
                }
            case .keyboardRightArrow, .keyboardDownArrow:
                if xmods.isEmpty {
                    collapseXSel(toOrderedStart: false)
                    return true
                }
                if xmods == [.shift] {
                    resetArrowGoal()
                    if xselExtend(
                        dir: code == .keyboardRightArrow
                            ? .right : .down) {
                        return true
                    }
                    collapseXSel()
                    return false
                }
            default:
                break
            }
            let chars = key.characters
            if xmods.isEmpty || xmods == [.shift],
               chars.count == 1,
               chars.unicodeScalars.allSatisfy({
                   !CharacterSet.controlCharacters
                       .contains($0)
               }) {
                // 覆打：无命令/控制修饰的单字符键
                // （Web xk.length === 1 支）；控制字
                // 符（Tab 等）不入、落下方收拢放行。
                resetArrowGoal()
                replaceXSel(text: chars, enter: false)
                return true
            }
            collapseXSel()
            return false
        }
        // F-09 二期：无 xsel 时 Shift+方向的跨块步
        // 进接管（Web keydown 的 else-if 支同位）——
        // 端点源 = 本视图原生选区两端（活动端推定
        // 见 EditorTextView.noteXSelSelection）；
        // 桥接层判块内步进/非边缘行内移动不接管
        // （返回 false）→ 落下方 mods 守卫放行原生
        // 块内扩展。组字中不接管（Web 组字守卫同
        // 位）；Cmd/Ctrl/Alt 组合不入（上方命令面
        // 已各行其道）。
        if tv.markedTextRange == nil,
           key.modifierFlags.contains(.shift),
           key.modifierFlags.intersection(
               [.alternate, .control, .command]).isEmpty {
            let sr = tv.selectedRange
            let nat = (blockId: blockId, loc: sr.location,
                       len: sr.length,
                       focusAtEnd: tv.xselFocusAtEnd)
            switch code {
            case .keyboardLeftArrow:
                if xselExtend(dir: .left, native: nat) {
                    resetArrowGoal()
                    return true
                }
            case .keyboardRightArrow:
                if xselExtend(dir: .right, native: nat) {
                    resetArrowGoal()
                    return true
                }
            case .keyboardUpArrow:
                if xselExtend(dir: .up, native: nat) {
                    resetArrowGoal()
                    return true
                }
            case .keyboardDownArrow:
                if xselExtend(dir: .down, native: nat) {
                    resetArrowGoal()
                    return true
                }
            default:
                break
            }
        }
        // B-05 块末前向删除并块（硬件键盘 Delete，
        // 与段首退格对称）：无修饰、非组字、折叠光
        // 标落块末才接管；不在块末放行原生删下一
        // 字。斜杠面板在位不接管（其按键支已先行
        // 处理导航键，Delete 落到此处须让路）。
        if code == .keyboardDeleteForward,
           slashBlockId == nil,
           key.modifierFlags.intersection(
               [.shift, .alternate, .control, .command])
               .isEmpty,
           tv.markedTextRange == nil,
           tv.selectedRange.length == 0,
           tv.selectedRange.location
               == (tv.text as NSString).length {
            return mergeForwardFromKey(blockId: blockId)
        }
        let dir: String
        switch code {
        case .keyboardUpArrow: dir = "↑"
        case .keyboardDownArrow: dir = "↓"
        case .keyboardLeftArrow: dir = "←"
        case .keyboardRightArrow: dir = "→"
        default:
            resetArrowGoal()
            return false
        }
        if dir == "←" || dir == "→" { resetArrowGoal() }
        let mods = key.modifierFlags.intersection(
            [.shift, .alternate, .control, .command])
        guard mods.isEmpty else { return false }
        guard tv.markedTextRange == nil else { return false }
        guard tv.selectedRange.length == 0 else {
            return false
        }
        return crossBlockArrow(tv: tv, blockId: blockId,
                               dir: dir)
    }

    /// 跨块方向键（Web crossBlockArrow 逐支移植）：
    /// ←/→ 仅在块首/块尾跳相邻单元（首/尾）；↑↓ 按
    /// 视觉行量测——块内未跳跃过放行原生默认，跳跃
    /// 过或跨块按目标列窗口 X hit-test 相邻行、超
    /// 宽钳行尾。消费返回 true。
    func crossBlockArrow(tv: EditorTextView,
                         blockId: String, dir: String)
        -> Bool {
        let units = textUnits()
        guard let idx = units.firstIndex(where: {
            $0.block.id == blockId
        }) else { return false }
        let len = (tv.text as NSString).length
        let caret = tv.selectedRange.location
        switch dir {
        case "←":
            guard caret == 0, idx > 0 else { return false }
            return navFocus(units[idx - 1], offset: nil,
                            from: blockId, dir: dir)
        case "→":
            guard caret == len, idx < units.count - 1
            else { return false }
            return navFocus(units[idx + 1], offset: 0,
                            from: blockId, dir: dir)
        case "↑", "↓":
            let up = dir == "↑"
            let lines = lineBoxes(tv)
            guard let caretPos = tv.position(
                from: tv.beginningOfDocument, offset: caret)
            else { return false }
            let caretWin = tv.convert(
                tv.caretRect(for: caretPos), to: nil)
            if arrowGoalX == nil {
                arrowGoalX = caretWin.minX
            }
            let goalX = arrowGoalX ?? caretWin.minX
            // 当前视觉行（caretRect.minY 落行区间）。
            var li = lines.count - 1
            for (i, l) in lines.enumerated()
            where caretWin.minY >= l.rect.minY - 1
                && caretWin.minY < l.rect.maxY + 1 {
                li = i
                break
            }
            if lines.isEmpty { li = 0 }
            let inBlock = up ? li > 0 : li < lines.count - 1
            if inBlock {
                // 块内：未跳跃过放行原生默认移动。
                guard arrowManual else { return false }
                let target = lines[up ? li - 1 : li + 1]
                tv.selectedRange = NSRange(
                    location: hitOffset(tv: tv, line: target,
                                        xWindow: goalX),
                    length: 0)
                return true
            }
            // 跨块：相邻单元的目标行（↑ 取末行、↓ 取
            // 首行）按目标列 hit-test；无行量测（空
            // 块）退化 ↑ 末尾/↓ 首（Web setCaretEdge
            // 兜底的原生对应）。
            let nIdx = up ? idx - 1 : idx + 1
            guard nIdx >= 0, nIdx < units.count else {
                return false
            }
            let unit = units[nIdx]
            guard let tv2 = tvForBlock(unit.block.id) else {
                // 目标视图未注册（理论不可达：整页同
                // 帧渲染）：退 focusBlockId 块首落焦。
                focusBlockId = unit.block.id
                DiagLog.shared.log(
                    .info,
                    "EDIT caret cross-block \(dir) from \(blockId)")
                return true
            }
            let lines2 = lineBoxes(tv2)
            var offset: Int
            if lines2.isEmpty {
                offset = up
                    ? (tv2.text as NSString).length : 0
            } else {
                let target = up ? lines2[lines2.count - 1]
                    : lines2[0]
                offset = hitOffset(tv: tv2, line: target,
                                   xWindow: goalX)
            }
            arrowManual = true
            return navFocus(unit, offset: offset,
                            tv: tv2, from: blockId, dir: dir)
        default:
            return false
        }
    }

    /// 跨块落焦兑现：目标视图同步成第一响应者 + 定
    /// 选区（offset nil = 文本末尾），记 Diag（Web
    /// dispatch caretMove 同式）。
    private func navFocus(_ unit: NavUnit, offset: Int?,
                          tv known: EditorTextView? = nil,
                          from: String, dir: String) -> Bool {
        guard let tv2 = known ?? tvForBlock(unit.block.id)
        else {
            focusBlockId = unit.block.id
            DiagLog.shared.log(
                .info,
                "EDIT caret cross-block \(dir) from \(from)")
            return true
        }
        let len = (tv2.text as NSString).length
        let off = min(max(offset ?? len, 0), len)
        tv2.becomeFirstResponder()
        tv2.selectedRange = NSRange(location: off, length: 0)
        if dir == "↑" || dir == "↓" { arrowManual = true }
        DiagLog.shared.log(
            .info,
            "EDIT caret cross-block \(dir) from \(from)")
        return true
    }

    /// 视觉行盒（TextKit 2 行片段量测，坐标统一到
    /// 窗口系与 caretRect 同口径）：片段帧 + 行
    /// typographicBounds + 容器内距。可见性内部
    /// 级（跨文件共用，见 tvForBlock 注）。
    struct LineBox {
        var range: NSRange
        var rect: CGRect
    }

    func lineBoxes(_ tv: EditorTextView)
        -> [LineBox] {
        guard let lm = tv.textLayoutManager else { return [] }
        lm.ensureLayout(for: lm.documentRange)
        var out: [LineBox] = []
        let docStart = lm.documentRange.location
        lm.enumerateTextLayoutFragments(
            from: docStart, options: [.ensuresLayout]
        ) { frag in
            let fragStart = lm.offset(
                from: docStart, to: frag.rangeInElement.location)
            for line in frag.textLineFragments {
                var r = line.typographicBounds
                r.origin.x += frag.layoutFragmentFrame.origin.x
                    + tv.textContainerInset.left
                r.origin.y += frag.layoutFragmentFrame.origin.y
                    + tv.textContainerInset.top
                let win = tv.convert(r, to: nil)
                out.append(LineBox(
                    range: NSRange(
                        location: fragStart
                            + line.characterRange.location,
                        length: line.characterRange.length),
                    rect: win))
            }
            return true
        }
        return out
    }

    /// 行内目标列 hit-test（Web caretRangeFromPoint
    /// 的原生等价）：逐偏移取 caretRect 窗口 X、取
    /// 最近者；X 超行尾钳到行末偏移。
    func hitOffset(tv: EditorTextView, line: LineBox,
                   xWindow: CGFloat) -> Int {
        let len = (tv.text as NSString).length
        let start = line.range.location
        let end = min(line.range.location
            + line.range.length, len)
        guard end > start else { return start }
        var best = start
        var bestD = CGFloat.greatestFiniteMagnitude
        for off in start...end {
            guard let pos = tv.position(
                from: tv.beginningOfDocument, offset: off)
            else { continue }
            let x = tv.convert(tv.caretRect(for: pos),
                               to: nil).minX
            let d = abs(x - xWindow)
            if d < bestD {
                bestD = d
                best = off
            }
        }
        return best
    }

    /// 文本变化时跟随（Web 桥 processInput 口径）：光标
    /// 前最后一个「/」起、无空白至光标为 token（块内任意
    /// 位置可触发，含列表项）；URL 形 token 抑制；查询
    /// ≤30 字。token 区间与选区以字符偏移记下，执行时
    /// 按偏移剥离/包裹（审计 C S-1/S-3）。
    func updateSlash(for block: BlockState,
                     selUTF16: NSRange,
                     caretX: CGFloat? = nil,
                     caretLineTop: CGFloat? = nil,
                     caretLineBottom: CGFloat? = nil) {
        // 触发面守卫集（M-01，Web 口径对齐）：Web
        // 于 heading/quote 内不弹（原版 use-slash +
        // blockquote 守卫，audit2 §3.2）；此前仅排
        // codeBlock/callout，heading/quote 仍可弹。
        // 对齐后可弹集 = paragraph / todo / list-item。
        let eligible = (block.isText
            || block.type == "list-item")
            && block.type != "codeBlock"
            && block.type != "callout"
            && block.type != "heading"
            && block.type != "quote"
        guard eligible else {
            if slashBlockId == block.id { slashBlockId = nil }
            return
        }
        let ns = block.text as NSString
        let start16 = min(selUTF16.location, ns.length)
        let end16 = min(selUTF16.location
            + selUTF16.length, ns.length)
        let selStart = ns.substring(to: start16).count
        let caret = ns.substring(to: end16).count
        let selLen = caret - selStart
        let chars = Array(block.text)
        var tokenStart: Int? = nil
        var i = caret
        while i > 0 {
            let c = chars[i - 1]
            if c == " " || c == "\n" || c == "\t" || c == "　" {
                break
            }
            if c == "/" { tokenStart = i - 1; break }
            i -= 1
        }
        func close() {
            if slashBlockId == block.id {
                slashBlockId = nil
            }
        }
        guard let ts = tokenStart else { close(); return }
        // URL 抑制（B-04/m-03 根治，Web editor.js
        // processInput 逐字移植）：含本斜杠的非空白
        // token（自斜杠向前至空白为止、含斜杠本身）
        // 剥前导括号引号后，大小写不敏感地以
        // http://、https:// 或 www. 开头者抑制——该
        // 斜杠是手打 URL 的一部分、非命令触发。旧
        // 口径（前字为 : 或 / 抑制 + 所在词词首判、
        // 大小写敏感、无剥除）在 HTTP://、(www. 等
        // 形态与 Web 分叉，已废。
        var tokStart = ts
        while tokStart > 0
            && !chars[tokStart - 1].isWhitespace {
            tokStart -= 1
        }
        var tok = String(chars[tokStart...ts])
        let leadChars: Set<Character> = [
            "(", "[", "{", "<", "\"", "'", "‘",
        ]
        while let f = tok.first, leadChars.contains(f) {
            tok.removeFirst()
        }
        let tokLow = tok.lowercased()
        if tokLow.hasPrefix("http://")
            || tokLow.hasPrefix("https://")
            || tokLow.hasPrefix("www.") {
            close()
            return
        }
        let query = String(chars[(ts + 1)..<caret])
        guard query.count <= 30 else { close(); return }
        if let caretX { slashAnchorX = caretX }
        if let caretLineTop, let caretLineBottom {
            // 纵向行锚与触发块绑定（B-03）：面板只
            // 对绑定块用行锚，异块/缺失走块底回退。
            slashAnchorTopY = caretLineTop
            slashAnchorBottomY = caretLineBottom
            slashAnchorBlockId = block.id
        }
        if slashBlockId != block.id || slashQuery != query {
            // 新开面板/查询变更：选中归零（首行）。
            slashSel = 0
        }
        if slashBlockId != block.id {
            // 面板新开打点（结果侧量测）：锚点 X 在位
            // 与否据此判读 F18 链路。
            DiagLog.shared.log(.info,
                "SLASH open id=\(block.id) "
                + "anchorX=\(Int(slashAnchorX))")
        }
        slashBlockId = block.id
        slashQuery = query
        slashTokenStart = ts
        slashTokenLen = caret - ts
        slashSelStart = selStart
        slashSelLen = selLen
    }

    // token 区间与触发选区（字符偏移，与 runs 同口径）。
    private var slashTokenStart = 0
    private var slashTokenLen = 0
    private var slashSelStart = 0
    private var slashSelLen = 0
    private var linkSelStart = 0
    private var linkSelLen = 0
    private var linkTokenStart = 0
    // F-13 延迟剥离：打开表单时 token 未剥，本
    // 字段记其长，提交（applyLink）时据此剥除。
    private var linkTokenLen = 0
    /// 音乐输入胶囊的聚焦请求（斜杠 musicCard 落点）。
    @Published var focusMusicId: String?

    /// runs 按字符区间删除（token 剥离），同步 text。
    private func removeRunRange(_ b: BlockState, start: Int,
                                len: Int) {
        guard len > 0 else { return }
        var out: [[String: Any]] = []
        var pos = 0
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            let rEnd = pos + rl
            if rEnd <= start || pos >= start + len {
                out.append(r)
            } else {
                let cutL = max(0, start - pos)
                let cutR = min(rl, start + len - pos)
                let kept = String(t.prefix(cutL))
                    + String(t.dropFirst(cutR))
                if !kept.isEmpty {
                    var nr = r
                    nr["text"] = kept
                    out.append(nr)
                }
            }
            pos = rEnd
        }
        b.runs = out
        var cs = Array(b.text)
        let lo = max(0, min(start, cs.count))
        let hi = max(lo, min(start + len, cs.count))
        cs.removeSubrange(lo..<hi)
        b.text = String(cs)
        b.nodeVersion += 1
    }

    /// runs 区间打标记（必要时在边界切分 run）。
    private func markRunRange(_ b: BlockState, start: Int,
                              len: Int, key: String,
                              value: Any = true) {
        guard len > 0 else { return }
        var out: [[String: Any]] = []
        var pos = 0
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            let segS = max(pos, start)
            let segE = min(pos + rl, start + len)
            if segS >= segE {
                out.append(r)
                pos += rl
                continue
            }
            let l = segS - pos
            let rr = segE - pos
            if l > 0 {
                var a = r
                a["text"] = String(t.prefix(l))
                out.append(a)
            }
            var mid = r
            mid["text"] = String(t.dropFirst(l)
                .prefix(rr - l))
            mid[key] = value
            out.append(mid)
            if rr < rl {
                var c = r
                c["text"] = String(t.dropFirst(rr))
                out.append(c)
            }
            pos += rl
        }
        b.runs = out
        b.nodeVersion += 1
    }

    /// runs 指定字符偏移插入一个 run，同步 text。
    private func insertRun(_ b: BlockState, at: Int,
                           run: [String: Any]) {
        let insText = run["text"] as? String ?? ""
        var out: [[String: Any]] = []
        var pos = 0
        var done = false
        for r in b.runs {
            let t = r["text"] as? String ?? ""
            let rl = t.count
            if !done && at >= pos && at <= pos + rl {
                let l = at - pos
                if l > 0 {
                    var a = r
                    a["text"] = String(t.prefix(l))
                    out.append(a)
                }
                out.append(run)
                if l < rl {
                    var c = r
                    c["text"] = String(t.dropFirst(l))
                    out.append(c)
                }
                done = true
            } else {
                out.append(r)
            }
            pos += rl
        }
        if !done { out.append(run) }
        b.runs = out
        var cs = Array(b.text)
        cs.insert(contentsOf: Array(insText),
                  at: max(0, min(at, cs.count)))
        b.text = String(cs)
        b.nodeVersion += 1
    }

    /// token 剥离后的选区修正（Web applyInline 偏移
    /// 口径）。参数化（F-13）：即时剥离（applyInline-
    /// Slash 传 slash* 快照）与提交延迟剥离（apply-
    /// Link 传 link* 快照）共用同一换算，两路落点同。
    private func adjustedSel(_ s0: Int, _ l0: Int,
                             tokenStart ts: Int,
                             tokenLen tl: Int) -> (Int, Int) {
        var s = s0
        var l = l0
        let te = ts + tl
        if s >= te {
            s -= tl
        } else if s + l > ts {
            let overlap = min(s + l, te) - max(s, ts)
            l = max(0, l - overlap)
            if s > ts { s = ts }
        }
        return (s, l)
    }

    /// 选区首尾空白外置（Web 口径）：全空白选区不收缩。
    private func trimmedSel(_ b: BlockState, _ s: Int,
                            _ l: Int) -> (Int, Int) {
        let cs = Array(b.text)
        guard l > 0, s >= 0, s + l <= cs.count
        else { return (s, l) }
        var lead = 0
        while lead < l && cs[s + lead].isWhitespace {
            lead += 1
        }
        var trail = 0
        while trail < l - lead
            && cs[s + l - 1 - trail].isWhitespace {
            trail += 1
        }
        if lead + trail >= l { return (s, l) }
        return (s + lead, l - lead - trail)
    }

    private func trailingParagraph(after b: BlockState)
        -> BlockState {
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let i = blocks.firstIndex(where: { $0 === b }) {
            blocks.insert(p, at: i + 1)
        } else {
            blocks.append(p)
        }
        return p
    }

    /// runs 按行切分（行内标记随行保留）：以 run
    /// 文本内的 \n 为界、标记键随片段复制；行集
    /// 尾随空行按 Rust lines() 口径摘一（全文以
    /// \n 结尾时末行空段不计）。
    private func runsSplitByLine(_ runs: [[String: Any]])
        -> [[[String: Any]]] {
        var lines: [[[String: Any]]] = [[]]
        var fullText = ""
        for r in runs {
            let t = r["text"] as? String ?? ""
            fullText += t
            if t.isEmpty { continue }
            let parts = t.components(separatedBy: "\n")
            for (k, p) in parts.enumerated() {
                if k > 0 { lines.append([]) }
                if !p.isEmpty {
                    var nr = r
                    nr["text"] = p
                    lines[lines.count - 1].append(nr)
                }
            }
        }
        if fullText.hasSuffix("\n"), lines.count > 1,
           lines[lines.count - 1].isEmpty {
            lines.removeLast()
        }
        return lines
    }

    /// MD 源段落的纯内容行（Web strip_md_prefixes
    /// 的真块型等价，M-05）：经 md_parse_json 同
    /// 一解析器（与 Web strip 所用 classify 同源
    /// core）取载荷——Code 取 code 逐行、List 取
    /// 各项 segs、Callout/Quote 取各段 segs、
    /// Heading 取标题 segs；行内标记经 MdRender
    /// .runs 保真为真 runs（F-07 口径：原生保
    /// runs 优于 Web 的源段落形态）。Rich/Table/
    /// Divider 三类 Web strip 为恒等、非 MD 段落
    /// 同——一律返回 nil 走 runs 原路（恒等价）；
    /// 解析形态与分类不符、子块无 segs 时亦回
    /// nil 兜底（保内容优先于剥前缀）。解析直调
    /// FFI 不走 mdKind/mdBlocks 缓存对：该缓存在
    /// 文本变更时只清 blocks 不复位 done 标记，
    /// 转换路径若经它取树可能读到陈旧空树致剥
    /// 前缀静默失效（隐患定性见 E3 报告，归预览
    /// 领地另行处置）。
    private func stripMdLineRuns(_ b: BlockState)
        -> [[[String: Any]]]? {
        guard b.type == "paragraph" else { return nil }
        let kind = mdKind(for: b)
        guard ["Code", "List", "Callout", "Quote",
               "Heading"].contains(kind) else {
            return nil
        }
        let json = mdParseJson(text: b.text)
        let parsed = (try? JSONSerialization.jsonObject(
            with: Data(json.utf8))) as? [Any] ?? []
        guard let first = parsed.first,
              let d = first as? [String: Any],
              let k = d.keys.first, k == kind,
              let v = d[k] as? [String: Any]
        else { return nil }
        func plainLines(_ s: String) -> [[[String: Any]]] {
            var ls = s.components(separatedBy: "\n")
                .map { $0.isEmpty
                    ? [[String: Any]]()
                    : [["text": $0]] }
            if s.hasSuffix("\n"), ls.count > 1 {
                ls.removeLast()
            }
            return ls
        }
        switch kind {
        case "Code":
            return plainLines(v["code"] as? String ?? "")
        case "List":
            return (v["items"] as? [Any] ?? []).map {
                MdRender.runs(
                    ($0 as? [String: Any])?["segs"]
                        as? [Any] ?? [])
            }
        case "Callout", "Quote":
            var out: [[[String: Any]]] = []
            for sub in v["blocks"] as? [Any] ?? [] {
                guard let sd = sub as? [String: Any],
                      let sk = sd.keys.first,
                      let sv = sd[sk] as? [String: Any],
                      let segs = sv["segs"] as? [Any]
                else { return nil }
                out.append(MdRender.runs(segs))
            }
            return out
        case "Heading":
            return [MdRender.runs(
                v["segs"] as? [Any] ?? [])]
        default:
            return nil
        }
    }

    /// 转列表的行集（F-06/M-05）：MD 源段落先剥
    /// 前缀取纯内容行，其余按 runs 内换行逐行切分。
    private func listLineRuns(_ b: BlockState)
        -> [[[String: Any]]] {
        if let stripped = stripMdLineRuns(b) {
            return stripped
        }
        return runsSplitByLine(b.runs)
    }

    /// 行 runs 以 \n 连接成单块 runs（转提示取纯
    /// 内容后重组正文用）。
    private func joinedLineRuns(
        _ lines: [[[String: Any]]]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for (i, lr) in lines.enumerated() {
            if i > 0 { out.append(["text": "\n"]) }
            out += lr
        }
        return out
    }

    /// 列表项升格：把列表项提出为独立段落（原列表按
    /// 前/后项拆成两段，尾段有序编号续接），返回升格
    /// 后的段落状态，供块型命令按顶层口径继续转换。
    private func promoteListItem(list: BlockState,
                                 item: BlockState)
        -> BlockState {
        guard let li = blocks.firstIndex(
                where: { $0 === list }),
              let ii = list.itemStates.firstIndex(
                where: { $0 === item })
        else { return item }
        let before = Array(list.itemStates[..<ii])
        let after = Array(list.itemStates[(ii + 1)...])
        let promoted = BlockState(node: [
            "id": item.id,
            "type": "paragraph",
            "children": BlockState.childrenFrom(
                runs: item.runs),
        ])
        promoted.runs = item.runs
        promoted.text = item.text
        blocks.remove(at: li)
        var insertAt = li
        if !before.isEmpty {
            list.itemStates = before
            list.nodeVersion += 1
            blocks.insert(list, at: insertAt)
            insertAt += 1
        }
        blocks.insert(promoted, at: insertAt)
        insertAt += 1
        if !after.isEmpty {
            var n = list.node
            n["id"] = "b-" + UUID().uuidString
                .prefix(8).lowercased()
            n["children"] = [[String: Any]]()
            if list.type == "numbered-list" {
                var attrs = n["attrs"] as? [String: Any]
                    ?? [:]
                let start0 = attrs["start"] as? Int ?? 1
                attrs["start"] = start0 + before.count + 1
                n["attrs"] = attrs
            }
            let tail = BlockState(node: n)
            tail.itemStates = after
            blocks.insert(tail, at: insertAt)
        }
        return promoted
    }

    /// 行内斜杠命令（Web applyInline 口径）：剥 token 后
    /// 按修正选区包裹；无选区插入占位「文字」并打标，
    /// 光标落其后。link 转链接表单（提交时按选区挂链
    /// 或插入字面链接）。
    private func applyInlineSlash(_ act: String,
                                  on b: BlockState) {
        if act == "link" {
            // F-13 延迟剥离（根治取消丢字）：打开表
            // 单只记账——token 不剥、选区记剥前原坐
            // 标；提交（applyLink）时才剥除并以同一
            // 换算映射选区。取消/Esc 只清会话字段，
            // 原文一字不动（Web openSlashLink 保留
            // 会话、submit 才剥 token 同口径）。
            linkSelStart = slashSelStart
            linkSelLen = slashSelLen
            linkTokenStart = slashTokenStart
            linkTokenLen = slashTokenLen
            linkFormBlockId = b.id
            return
        }
        removeRunRange(b, start: slashTokenStart,
                       len: slashTokenLen)
        var (s, l) = adjustedSel(slashSelStart,
                                 slashSelLen,
                                 tokenStart: slashTokenStart,
                                 tokenLen: slashTokenLen)
        (s, l) = trimmedSel(b, s, l)
        if l > 0 {
            if act == "highlight" {
                insertRun(b, at: s + l, run: ["text": "=="])
                insertRun(b, at: s, run: ["text": "=="])
                pendingCaretOffset = s + l + 2
            } else if act == "mathInline" {
                // 行内公式（原生增强，原版无）：与高亮
                // 同族——$ 是字面文本（编辑态保留字面、
                // 预览经 core has_math_syntax/split_math
                // 切分），不入 runs 标记模型。
                insertRun(b, at: s + l, run: ["text": "$"])
                insertRun(b, at: s, run: ["text": "$"])
                pendingCaretOffset = s + l + 1
            } else {
                markRunRange(b, start: s, len: l, key: act)
                pendingCaretOffset = s + l
            }
        } else {
            let at = slashTokenStart
            if act == "highlight" {
                insertRun(b, at: at, run: ["text": "==文字=="])
                pendingCaretOffset = at + 6
            } else if act == "mathInline" {
                // 无选区口径与高亮一致：字面标记 + 占
                // 位「文字」、光标落其后（既有无选区口
                // 径无「空标记光标居中」先例）。
                insertRun(b, at: at, run: ["text": "$文字$"])
                pendingCaretOffset = at + 4
            } else {
                insertRun(b, at: at,
                          run: ["text": "文字", act: true])
                pendingCaretOffset = at + 2
            }
        }
        focusBlockId = b.id
        focusCaretEnd = false
    }

    /// 斜杠命令执行（Web 分流口径）：行内命令就地标记；
    /// 图片/画廊落占位块 + 尾随空段；其余转块型。触发
    /// 块可在顶层或列表项内（块型命令先升格）。
    func applySlash(_ act: String) {
        guard let bid = slashBlockId else { return }
        var found: BlockState?
        var parentList: BlockState?
        if let b = blocks.first(where: { $0.id == bid }) {
            found = b
        } else {
            for l in blocks where l.isList {
                if let it = l.itemStates.first(
                    where: { $0.id == bid }) {
                    found = it
                    parentList = l
                    break
                }
            }
        }
        guard let target = found
        else {
            DiagLog.shared.log(.warn,
                "EDIT slash target missing "
                + "\(slashBlockId ?? "?")")
            slashBlockId = nil
            return
        }
        // link 例外：表单在斜杠面板内原地替换列表，
        // 会话保留到表单收口；最近使用也改到提交成功
        // 时记录（Web 口径）。F-13：开表单不压历史、
        // 不落盘——历史在提交时由 applyLink 压栈，
        // 取消路径零副作用（原文不丢字、无幽灵撤销
        // 步）。
        if act != "link" {
            slashBlockId = nil
            SlashCmds.recordRecent(act)
            pushHistory()
        }
        let inlineActs: Set<String> = [
            "bold", "italic", "code", "strikethrough",
            "highlight", "link", "mathInline",
        ]
        if inlineActs.contains(act) {
            applyInlineSlash(act, on: target)
            if act != "link" { scheduleSave() }
            DiagLog.shared.log(.info,
                "EDIT slash \(act) \(target.id)")
            return
        }
        removeRunRange(target, start: slashTokenStart,
                       len: slashTokenLen)
        // 列表项 × 列表命令 = 整表换型（F-04，Web
        // op_convert Item 臂）：只改父表 type 并清
        // start，项集/序/runs 全保留，不升格拆表；
        // 落点回触发项 token 起点（Web D-11 同位）。
        if let list = parentList,
           act == "bulletList" || act == "numberList" {
            var n = list.node
            n["type"] = act == "bulletList"
                ? "bulleted-list" : "numbered-list"
            if var attrs = n["attrs"] as? [String: Any] {
                attrs.removeValue(forKey: "start")
                n["attrs"] = attrs.isEmpty ? nil : attrs
            }
            list.node = n
            list.nodeVersion += 1
            focusBlockId = target.id
            focusCaretEnd = false
            pendingCaretOffset = min(slashTokenStart,
                                     target.text.count)
            scheduleSave()
            DiagLog.shared.log(.info,
                "EDIT slash \(act) \(target.id)")
            return
        }
        var b = target
        if let list = parentList {
            b = promoteListItem(list: list, item: target)
        }
        func convert(_ type: String,
                     level: Int? = nil) {
            // children 以当前 runs 重组（token 已剥
            // 离），类型字段走转换单点（清旧设新，
            // E3）；calloutType 不在此写——重转保
            // 留变体、新转入缺省 note（M-04）。
            var n = b.node
            n["children"] = BlockState.childrenFrom(
                runs: b.runs)
            b.node = n
            convertNodeType(b, type: type,
                            level: level ?? 2)
            b.text = b.runs.compactMap {
                $0["text"] as? String
            }.joined()
            b.nodeVersion += 1
        }
        switch act {
        case "heading1": convert("heading", level: 1)
        case "heading2": convert("heading", level: 2)
        case "heading3": convert("heading", level: 3)
        case "paragraph": convert("paragraph")
        case "quote": convert("quote")
        case "todo":
            convert("todo")
            // 尾随空段（M-03）：顶层路径补（Web
            // op_convert Top 臂口径）；列表项升格
            // 路 Web Item 臂不补、同口径不补。
            if parentList == nil {
                ensureTrailingEmptyPara(after: b)
            }
        case "codeBlock": convert("codeBlock")
        case "mathBlock":
            // 公式块（原生增强，原版无）：$$ 围栏包
            // 裹既有正文后走段落转换落盘（MD 公式无
            // 独立块型，段落即其落盘形态）；失焦预览
            // 经 core 切分，独占段成块级公式（md.rs
            // 独占段 Math 分支）。B-01 根治：旧整体
            // 替换 runs 静默弃正文，与其余 23 项转换
            // 保内容通例分叉；改以围栏两行夹住原
            // runs（行内标记随行保留），正文为空时
            // 产出与旧围栏三行逐字同。光标落中行行
            // 首（偏移 3），尾段统一落点不覆盖（已
            // 入下方排除名单）。
            if b.text.isEmpty {
                b.runs = [["text": "$$\n\n$$"]]
            } else {
                b.runs = [["text": "$$\n"]] + b.runs
                    + [["text": "\n$$"]]
            }
            convert("paragraph")
            focusBlockId = b.id
            focusCaretEnd = false
            pendingCaretOffset = 3
        case "callout":
            // M-05：顶层 MD 源段落先剥前缀取纯内
            // 容再转（Web strip 后入 Callout 臂）；
            // 列表项升格路 Web Item 臂不剥、同口
            // 径不剥。转代码块例外不剥——真块型
            // 口径下正文原样入 codeBlock（F-07 定
            // 案：保 runs），与 Web 围栏臂保留原文
            // 同果（D-13）。
            if parentList == nil,
               let lines = stripMdLineRuns(b) {
                b.runs = joinedLineRuns(lines)
            }
            convert("callout")
            // 尾随空段：顶层路径补（Web op_convert
            // 顶层臂 callout 与 todo 同臂，斜杠审计
            // S7）；列表项升格路 Web Item 臂不补、
            // 同口径不补。
            if parentList == nil {
                ensureTrailingEmptyPara(after: b)
            }
        case "divider":
            b.node = ["id": b.id, "type": "divider"]
            b.nodeVersion += 1
            let p = trailingParagraph(after: b)
            focusBlockId = p.id
            focusCaretEnd = false
        case "bulletList", "numberList":
            // 逐行拆项（F-06）：多行文本按行成项
            // （MD 源段落先剥前缀，M-05；行集口径
            // 见 listLineRuns）。本 case 只达顶层源
            // （列表项 × 列表命令已在上方整表换型
            // 早路返回）。
            let lineRuns = listLineRuns(b)
            var items: [BlockState] = []
            for lr in lineRuns {
                let item = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "list-item",
                    "children": BlockState.childrenFrom(
                        runs: lr),
                ])
                item.runs = lr
                item.text = lr.compactMap {
                    $0["text"] as? String
                }.joined()
                items.append(item)
            }
            if items.isEmpty {
                let item = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "list-item",
                    "children": [[String: Any]](),
                ])
                items.append(item)
            }
            b.node = [
                "id": b.id,
                "type": act == "bulletList"
                    ? "bulleted-list" : "numbered-list",
                "children": [],
            ]
            b.itemStates = items
            b.nodeVersion += 1
            // 落点回 token 所在行/行内偏移（token 已
            // 剥离，按剥离后文本计行）；单行时与旧口
            // 径同值。
            let pre = String(b.text.prefix(
                min(slashTokenStart, b.text.count)))
            let caretLine = pre.filter { $0 == "\n" }.count
            let lineOff = pre.split(
                separator: "\n",
                omittingEmptySubsequences: false)
                .last?.count ?? 0
            let ci = items[min(caretLine, items.count - 1)]
            focusBlockId = ci.id
            focusCaretEnd = false
            pendingCaretOffset = min(lineOff, ci.text.count)
        case "image", "gallery":
            if act == "image" {
                b.node = ["id": b.id, "type": "image",
                          "attrs": [String: Any]()]
            } else {
                b.node = ["id": b.id, "type": "gallery",
                          "attrs": ["items":
                            [[String: Any]]()] as [String: Any]]
            }
            b.nodeVersion += 1
            // 尾随已有空段则直接落焦，不重复插（Web
            // next-empty 口径）。
            if let i = blocks.firstIndex(
                where: { $0 === b }),
               i + 1 < blocks.count,
               blocks[i + 1].type == "paragraph",
               blocks[i + 1].text.isEmpty {
                focusBlockId = blocks[i + 1].id
            } else {
                let p = trailingParagraph(after: b)
                focusBlockId = p.id
            }
            focusCaretEnd = false
        case "imgTextCard", "imageTextRow":
            // 占位文案落数据（原版口径），尾随空段承接
            // 焦点（原子卡本身无文本面可落）。
            let ph = act == "imgTextCard"
                ? "点击输入文字" : "点击输入说明文字"
            b.node = ["id": b.id, "type": act, "text": ph]
            b.text = ph
            b.nodeVersion += 1
            let p = trailingParagraph(after: b)
            focusBlockId = p.id
            focusCaretEnd = false
        case "musicCard":
            b.node = ["id": b.id, "type": "musicCard",
                      "status": "input", "url": ""]
            b.nodeVersion += 1
            _ = trailingParagraph(after: b)
            // 焦点落输入胶囊本身（Web 口径）。
            focusMusicId = b.id
        default:
            break
        }
        if act != "divider" && act != "image"
            && act != "gallery" && act != "musicCard"
            && act != "bulletList" && act != "numberList"
            && act != "imgTextCard" && act != "imageTextRow"
            && act != "mathBlock" {
            // 转块型后光标落 token 起点（Web pos 口径）。
            focusBlockId = b.id
            focusCaretEnd = false
            pendingCaretOffset = min(slashTokenStart,
                                     b.text.count)
        }
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT slash \(act) \(b.id)")
    }

    /// 链接表单提交（Web applyLink 口径）：有选区按区
    /// 间挂链；无选区在 token 处插入字面 [链接文字](url)
    /// （URL 括号先转义）。
    @discardableResult
    func applyLink(url: String) -> Bool {
        guard let bid = linkFormBlockId else { return false }
        var found: BlockState?
        if let b = blocks.first(where: { $0.id == bid }) {
            found = b
        } else {
            for l in blocks where l.isList {
                if let it = l.itemStates.first(
                    where: { $0.id == bid }) {
                    found = it
                    break
                }
            }
        }
        guard let b = found
        else { linkFormBlockId = nil; return false }
        let trimmed = url.trimmingCharacters(
            in: .whitespaces)
        // 校验面（SL-16 随 B-04 批对齐）：Web
        // submit_slash_link 以 URL 解析 + 协议白
        // 名单（http:/https:）判；旧原生仅前缀判，
        // 「http://」空串、内含空白等不可解析形也
        // 放行（判定面更宽）。改解析口径：可解析、
        // scheme 为 http/https、host 非空才过。
        guard let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty
        else { return false }
        linkFormBlockId = nil
        slashBlockId = nil
        SlashCmds.recordRecent("link")
        pushHistory()
        // F-13 提交时剥 token：打开时只记账未剥，
        // 此刻剥除，再以打开同式换算（adjustedSel
        // + trimmedSel，序列与旧即时剥离逐字同）把
        // 快照选区映射到剥后坐标。无选区插入点
        // linkTokenStart 在剥后坐标系同位，不变。
        // 校验不过的提交在上方已 return，token 与
        // 正文俱在、不丢字。
        removeRunRange(b, start: linkTokenStart,
                       len: linkTokenLen)
        var (ls, ll) = adjustedSel(linkSelStart,
                                   linkSelLen,
                                   tokenStart: linkTokenStart,
                                   tokenLen: linkTokenLen)
        (ls, ll) = trimmedSel(b, ls, ll)
        linkSelStart = ls
        linkSelLen = ll
        if linkSelLen > 0 {
            markRunRange(b, start: linkSelStart,
                         len: linkSelLen, key: "_link",
                         value: trimmed)
            markRunRange(b, start: linkSelStart,
                         len: linkSelLen, key: "underline")
            pendingCaretOffset = linkSelStart + linkSelLen
        } else {
            let esc = trimmed
                .replacingOccurrences(of: "(", with: "%28")
                .replacingOccurrences(of: ")", with: "%29")
            let literal = "[链接文字](\(esc))"
            insertRun(b, at: linkTokenStart,
                      run: ["text": literal])
            pendingCaretOffset = linkTokenStart
                + literal.count
        }
        focusBlockId = b.id
        focusCaretEnd = false
        scheduleSave()
        return true
    }

    /// 标题/Callout 回车（Web 口径）：不拆文本，整段保
    /// 留、其后插空段落并落焦。
    func headingEnter(_ block: BlockState) {
        pushHistory()
        let p = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": "paragraph",
            "children": [["text": ""]],
        ])
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            blocks.insert(p, at: i + 1)
        } else {
            blocks.append(p)
        }
        focusBlockId = p.id
        focusCaretEnd = false
        scheduleSave()
    }

    // ── 卡片解析链（E19，Web cards.rs 口径） ──────
    /// 从任意文本提第一个 http(s) URL；无 scheme 时整段
    /// 须是裸域名形态才补 https://（逐项移植 Web
    /// extract_card_url 的字符集与校验口径）。
    static func extractCardURL(_ candidate: String)
        -> String? {
        let lower = candidate.lowercased()
        if let r = lower.range(of: "http://")
            ?? lower.range(of: "https://") {
            var idx = r.lowerBound
            var end = candidate.endIndex
            let extra = Set<Character>("-@:%._+~#=?&/()")
            while idx < candidate.endIndex {
                let ch = candidate[idx]
                let scalar = ch.unicodeScalars.first?.value
                    ?? 0
                let ok = ch.isLetter || ch.isNumber
                    || extra.contains(ch)
                    || (0x4e00...0x9fa5).contains(scalar)
                if !ok { end = idx; break }
                idx = candidate.index(after: idx)
                end = idx
            }
            let url = String(candidate[r.lowerBound..<end])
            return URL(string: url) != nil ? url : nil
        }
        let t = candidate.trimmingCharacters(
            in: .whitespaces)
        if t.isEmpty
            || t.contains(where: { $0.isWhitespace }) {
            return nil
        }
        let host = t.split(whereSeparator: {
            "/?#".contains($0)
        }).first.map(String.init) ?? t
        let parts = host.components(separatedBy: ".")
        guard parts.count >= 2,
              let tld = parts.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }),
              let name = parts.dropLast().last,
              !name.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber
                  || $0 == "-" || $0 == "." }) else {
            return nil
        }
        let url = "https://" + t
        return URL(string: url) != nil ? url : nil
    }

    static let musicHosts = ["music.163.com", "163cn.tv",
        "y.qq.com", "i.y.qq.com", "open.spotify.com",
        "music.apple.com"]

    /// 链接元数据（Web fetchLinkMeta：GET Worker /meta）。
    func fetchLinkMeta(_ url: String) async
        -> [String: Any]? {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~"))
        let enc = url.addingPercentEncoding(
            withAllowedCharacters: allowed) ?? url
        guard let u = URL(string:
            "https://mynote.overtrees.workers.dev/meta"
            + "?url=\(enc)") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await
            URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(
            with: data)) as? [String: Any]
    }

    /// 解析一张卡：拉 meta → title 非空 ready、否则
    /// error；竞态守卫 = 回写时 url 仍与发起时一致。
    func startResolveCard(_ block: BlockState) {
        guard let url = block.node["url"] as? String,
              !url.isEmpty else { return }
        Task { @MainActor in
            let meta = await self.fetchLinkMeta(url)
            guard (block.node["url"] as? String) == url
            else { return }
            var n = block.node
            if let meta,
               let t = meta["title"] as? String,
               !t.isEmpty {
                n["meta"] = meta
                n["status"] = "ready"
            } else {
                n["meta"] = NSNull()
                n["status"] = "error"
            }
            block.node = n
            block.nodeVersion += 1
            self.scheduleSave()
            DiagLog.shared.log(.info,
                "CARD resolve \(block.id) -> "
                + (n["status"] as? String ?? ""))
        }
    }

    /// 音乐输入胶囊提交（回车或粘出 URL 时）：提出 URL
    /// 才动作——节点转 loading 走公共解析；解析后光标
    /// 落卡下（下方非文本块则补空段）。
    func submitMusicInput(_ block: BlockState,
                          rawText: String) {
        guard block.type == "musicCard",
              (block.node["status"] as? String) == "input",
              let url = Self.extractCardURL(rawText)
        else { return }
        pushHistory()
        var n = block.node
        n["url"] = url
        n["meta"] = NSNull()
        n["status"] = "loading"
        block.node = n
        block.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "CARD music input resolve \(block.id) <- \(url)")
        startResolveCard(block)
        // 落点：卡下方现成文本块直接用，否则补空段。
        if let i = blocks.firstIndex(
            where: { $0 === block }) {
            if i + 1 < blocks.count,
               blocks[i + 1].isText {
                focusBlockId = blocks[i + 1].id
            } else {
                let p = trailingParagraph(after: block)
                focusBlockId = p.id
            }
            focusCaretEnd = false
        }
    }

    /// 粘贴成卡（Web op_paste_card 口径）：当前块留
    /// before 段，卡插其后（音乐域名 → musicCard、其余
    /// → link-card，status=loading 走公共解析），余文与
    /// after 段各成一段落，焦点按 Web 序落位。
    func pasteCard(block: BlockState, url: String,
                   remain: String,
                   beforeRuns: [[String: Any]],
                   afterRuns: [[String: Any]]) {
        guard let i = blocks.firstIndex(
            where: { $0 === block }) else { return }
        pushHistory()
        block.runs = beforeRuns
        block.text = beforeRuns.compactMap {
            $0["text"] as? String
        }.joined()
        block.nodeVersion += 1
        let isMusic = Self.musicHosts.contains {
            url.contains($0)
        }
        let card = BlockState(node: [
            "id": "b-" + UUID().uuidString
                .prefix(8).lowercased(),
            "type": isMusic ? "musicCard" : "link-card",
            "url": url, "status": "loading",
        ])
        var at = i + 1
        blocks.insert(card, at: at)
        at += 1
        var focus: (String, Bool)?  // (id, 落末尾?)
        let remainT = remain.trimmingCharacters(
            in: .whitespaces)
        if !remainT.isEmpty {
            let p = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": [["text": remainT]],
            ])
            p.runs = [["text": remainT]]
            p.text = remainT
            blocks.insert(p, at: at)
            at += 1
            focus = (p.id, true)
        }
        let afterText = afterRuns.compactMap {
            $0["text"] as? String
        }.joined()
        if !afterText.isEmpty {
            let p = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": BlockState.childrenFrom(
                    runs: afterRuns),
            ])
            p.runs = afterRuns
            p.text = afterText
            blocks.insert(p, at: at)
            at += 1
            if focus == nil { focus = (p.id, false) }
        }
        if focus == nil {
            let cardIdx = i + 1
            if cardIdx + 1 < blocks.count,
               blocks[cardIdx + 1].isText {
                focus = (blocks[cardIdx + 1].id, false)
            } else {
                let p = trailingParagraph(after: card)
                focus = (p.id, false)
            }
        }
        if let f = focus {
            focusBlockId = f.0
            focusCaretEnd = f.1
        }
        scheduleSave()
        startResolveCard(card)
    }

    /// 粘贴分流（Web paste 口径）：整段是裸 URL、或内嵌
    /// 媒体 URL 时成卡并消费粘贴；其余放行原生粘贴。
    /// before/after 由调用方按当前选区切好。
    func handlePaste(block: BlockState, text: String,
                     beforeRuns: [[String: Any]],
                     afterRuns: [[String: Any]]) -> Bool {
        // 块型守卫（M-02）：codeBlock 内粘贴恒留字
        // 面、不走成卡判定——Web 代码块全路（打字
        // 换行/多行粘贴/斜杠）皆字面口径，成卡会改
        // 写块 children 并在块后插卡、毁代码内容。
        // 返回 false 后上层走 super.paste 原生插入，
        // shouldChange 的 codeBlock 支放行块内换行。
        if block.type == "codeBlock" { return false }
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let mediaHosts = Self.musicHosts
            + ["b23.tv", "xiaohongshu.com", "xhslink.com"]
        // 整段裸 URL（无空白、scheme 开头、含域名点）。
        if !trimmed.contains(where: { $0.isWhitespace }),
           trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://"),
           let url = Self.extractCardURL(trimmed),
           url == trimmed {
            pasteCard(block: block, url: url, remain: "",
                      beforeRuns: beforeRuns,
                      afterRuns: afterRuns)
            return true
        }
        // 内嵌媒体 URL：提 URL 成卡，余文成段。
        if let url = Self.extractCardURL(trimmed),
           mediaHosts.contains(where: {
               url.contains($0) }) {
            let remain = trimmed.replacingOccurrences(
                of: url, with: "")
            pasteCard(block: block, url: url,
                      remain: remain,
                      beforeRuns: beforeRuns,
                      afterRuns: afterRuns)
            return true
        }
        return false
    }

    /// 列表项段首退格（Web 口径）：空项删项；首项转段落
    /// 移到列表前；其余并入上一项、光标落接合处。
    func mergeListItemBackward(list: BlockState,
                               item: BlockState) {
        guard let idx = list.itemStates.firstIndex(
            where: { $0 === item }) else { return }
        let li = blocks.firstIndex(where: { $0 === list })
        if idx == 0, let li {
            // T-14/T-15：首项退格按 prev_sibling 分类
            // （Web op_merge 口径），不再一律提出成段。
            if item.text.isEmpty {
                // 空首项：删项、光标向前跳过原子块落
                // 最近文本块末尾；无目标且列表只剩此
                // 项时整表转空段；再无路则无动作。
                if let target = nearestTextBlock(before: li) {
                    pushHistory()
                    list.itemStates.remove(at: 0)
                    if list.itemStates.isEmpty {
                        blocks.remove(at: li)
                    } else {
                        // 首项摘除、存续首项原号不
                        // 变 → start +1（F-05）。
                        shiftListStart(list, by: 1)
                    }
                    focusBlockId = target.id
                    focusCaretEnd = true
                } else if list.itemStates.count == 1 {
                    pushHistory()
                    let p = BlockState(node: [
                        "id": "b-" + UUID().uuidString
                            .prefix(8).lowercased(),
                        "type": "paragraph",
                        "children": [["text": ""]],
                    ])
                    blocks[li] = p
                    focusBlockId = p.id
                    focusCaretEnd = true
                    scheduleSave()
                    DiagLog.shared.log(.info,
                        "EDIT merge list-item \(item.id) "
                        + "case=whole-list")
                    return
                } else {
                    return
                }
            } else if li > 0, blocks[li - 1].isText,
                      !blocks[li - 1].isStructuralAtomic {
                // 非空首项 + 前为文本块：并入前块末
                // 尾，光标落接合处。结构守卫成员（代码
                // 块）除外——分类单点 isStructuralAtomic，
                // 落下方原子支只选中不并入。
                let prev = blocks[li - 1]
                pushHistory()
                let junction = prev.text.count
                prev.runs = prev.runs + item.runs
                prev.text = prev.text + item.text
                prev.nodeVersion += 1
                list.itemStates.remove(at: 0)
                if list.itemStates.isEmpty {
                    blocks.remove(at: li)
                } else {
                    shiftListStart(list, by: 1)
                }
                focusBlockId = prev.id
                focusCaretEnd = false
                pendingCaretOffset = junction
            } else if li > 0,
                      blocks[li - 1].isStructuralAtomic,
                      !(blocks[li - 1].isList
                        && !blocks[li - 1].itemStates
                            .isEmpty) {
                // F-08：非空首项段首退格撞原子前驱
                // ——Web op_merge 对 Item(li,0) 经
                // classify_top 同归原子支：不删不
                // 提，只把原子块带入选中态（与顶层
                // mergeBlockBackward 原子支同口径；
                // 此前误记「无动作」、实为死键）。分
                // 类 2026-11-28 起经 isStructuralAtomic
                // 单点（原 !isText 直判与之等价域外，
                // 新增代码块同入此支）。
                selectedBlockId = blocks[li - 1].id
                DiagLog.shared.log(.info,
                    "EDIT merge backspace before atomic "
                    + "\(blocks[li - 1].id) selected "
                    + "(kept)")
                return
            } else {
                // 无前块：不删不提、无动作（Web 无
                // prev 同口径）。
                return
            }
            list.nodeVersion += 1
            scheduleSave()
            let mergeCase = item.text.isEmpty
                ? "first-empty" : "first-merge"
            DiagLog.shared.log(.info,
                "EDIT merge list-item \(item.id) "
                + "case=\(mergeCase)")
            // 智能前缀尾扫（F-02，Web merge 消息尾）。
            applySmartPrefixIfNeeded()
            return
        }
        pushHistory()
        if item.text.isEmpty {
            list.itemStates.remove(at: idx)
            if list.itemStates.isEmpty {
                let p = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "paragraph",
                    "children": [["text": ""]],
                ])
                if let li = blocks.firstIndex(
                    where: { $0 === list }) {
                    blocks[li] = p
                }
                focusBlockId = p.id
                focusCaretEnd = true
            } else {
                let target = list.itemStates[
                    min(idx, list.itemStates.count - 1)]
                focusBlockId = target.id
                focusCaretEnd = true
            }
            DiagLog.shared.log(.info,
                "EDIT merge list-item \(item.id) case=empty")
        } else if idx == 0 {
            // li 缺失的兜底旧路（理论不达）：提出成段。
            list.itemStates.remove(at: idx)
            let p = BlockState(node: [
                "id": item.id,
                "type": "paragraph",
                "children": [["text": item.text]],
            ])
            p.runs = item.runs
            p.text = item.text
            if let li = blocks.firstIndex(
                where: { $0 === list }) {
                blocks.insert(p, at: li)
                if list.itemStates.isEmpty {
                    blocks.remove(at: li + 1)
                } else {
                    shiftListStart(list, by: 1)
                }
            }
            focusBlockId = p.id
            focusCaretEnd = true
            DiagLog.shared.log(.info,
                "EDIT merge list-item \(item.id) "
                + "case=promote")
        } else {
            let prev = list.itemStates[idx - 1]
            let junction = prev.text.count
            prev.runs = prev.runs + item.runs
            prev.text = prev.text + item.text
            prev.nodeVersion += 1
            list.itemStates.remove(at: idx)
            focusBlockId = prev.id
            focusCaretEnd = false
            pendingCaretOffset = junction
            DiagLog.shared.log(.info,
                "EDIT merge list-item \(item.id) case=merge")
        }
        list.nodeVersion += 1
        scheduleSave()
        // 智能前缀尾扫（F-02，Web merge 消息尾同位）。
        applySmartPrefixIfNeeded()
    }

    /// 列表项块末前向删除（B-05，mergeListItem-
    /// Backward 镜像）：非末项在表内处理（空项删
    /// 项落下一项块首、非空并入下一项）；末项按列
    /// 表的下一顶层块分类（文本并入项内、列表取
    /// 其首项、原子块选中、无后块无动作）；空末
    /// 项删项后向后跳过原子块落最近文本块块首，
    /// 无目标且表只剩此项时整表转空段。
    func mergeListItemForward(list: BlockState,
                              item: BlockState) {
        guard let idx = list.itemStates.firstIndex(
            where: { $0 === item }) else { return }
        let li = blocks.firstIndex(where: { $0 === list })
        if idx < list.itemStates.count - 1 {
            // 表内支（退格项内支镜像）。
            pushHistory()
            if item.text.isEmpty {
                list.itemStates.remove(at: idx)
                let target = list.itemStates[idx]
                focusBlockId = target.id
                focusCaretEnd = false
                pendingCaretOffset = 0
                DiagLog.shared.log(.info,
                    "EDIT merge list-item fwd "
                    + "\(item.id) case=empty")
            } else {
                let next = list.itemStates[idx + 1]
                let junction = item.text.count
                item.runs = item.runs + next.runs
                item.text = item.text + next.text
                item.nodeVersion += 1
                list.itemStates.remove(at: idx + 1)
                focusBlockId = item.id
                focusCaretEnd = false
                pendingCaretOffset = junction
                DiagLog.shared.log(.info,
                    "EDIT merge list-item fwd "
                    + "\(item.id) case=merge")
            }
            list.nodeVersion += 1
            scheduleSave()
            applySmartPrefixIfNeeded()
            return
        }
        // 末项支：须列表在顶层才有「下一块」可考；
        // 嵌套表末项无顶层后继、无动作（退格首项
        // li 缺失兜底同级口径）。
        guard let li else { return }
        if item.text.isEmpty {
            // 空末项（退格空首项镜像）：删项、向后
            // 跳过原子块落最近文本块块首；无目标且
            // 表只剩此项时整表转空段；再无路无动作。
            var diagCase: String?
            if let target = nearestTextBlock(
                after: li) {
                pushHistory()
                list.itemStates.remove(at: idx)
                if list.itemStates.isEmpty {
                    blocks.remove(at: li)
                } else {
                    list.nodeVersion += 1
                }
                focusBlockId = target.id
                focusCaretEnd = false
                pendingCaretOffset = 0
                diagCase = "last-empty"
            } else if list.itemStates.count == 1 {
                pushHistory()
                let p = BlockState(node: [
                    "id": "b-" + UUID().uuidString
                        .prefix(8).lowercased(),
                    "type": "paragraph",
                    "children": [["text": ""]],
                ])
                blocks[li] = p
                focusBlockId = p.id
                focusCaretEnd = false
                pendingCaretOffset = 0
                diagCase = "whole-list"
            }
            guard let diagCase else { return }
            scheduleSave()
            DiagLog.shared.log(.info,
                "EDIT merge list-item fwd "
                + "\(item.id) case=\(diagCase)")
            applySmartPrefixIfNeeded()
            return
        }
        guard li < blocks.count - 1 else { return }
        let next = blocks[li + 1]
        if next.isText && !next.isStructuralAtomic {
            pushHistory()
            let junction = item.text.count
            item.runs = item.runs + next.runs
            item.text = item.text + next.text
            item.nodeVersion += 1
            blocks.remove(at: li + 1)
            focusBlockId = item.id
            focusCaretEnd = false
            pendingCaretOffset = junction
            DiagLog.shared.log(.info,
                "EDIT merge list-item fwd "
                + "\(item.id) case=last-merge")
        } else if next.isList,
                  let first = next.itemStates.first {
            pushHistory()
            let junction = item.text.count
            item.runs = item.runs + first.runs
            item.text = item.text + first.text
            item.nodeVersion += 1
            next.itemStates.remove(at: 0)
            if next.itemStates.isEmpty {
                blocks.remove(at: li + 1)
            } else {
                shiftListStart(next, by: 1)
            }
            next.nodeVersion += 1
            focusBlockId = item.id
            focusCaretEnd = false
            pendingCaretOffset = junction
            DiagLog.shared.log(.info,
                "EDIT merge list-item fwd "
                + "\(item.id) case=last-list")
        } else {
            // 原子后继（F-08 镜像）：只带入选中态。
            selectedBlockId = next.id
            DiagLog.shared.log(.info,
                "EDIT merge fwd before atomic "
                + "\(next.id) selected (kept)")
            return
        }
        list.nodeVersion += 1
        scheduleSave()
        applySmartPrefixIfNeeded()
    }

    /// 拖拽态单点复位（M-10）：手势取消与行卸载两
    /// 路共用——除跟手量外，拾起骑乘的卡片/块菜单
    /// 一并按 id 清除，防取消后孤儿菜单残留在已复
    /// 位行上（Web 菜单会话随手势终局消亡、无此残
    /// 留面）。原地松手（onDrop → commitDrag）不
    /// 经此路：菜单留待点选是定案设计。
    func clearDragState(for id: String) {
        if draggingId == id {
            draggingId = nil
            dragDy = 0
        }
        if cardMenuBlockId == id {
            cardMenuBlockId = nil
        }
        if blockMenuBlockId == id {
            blockMenuBlockId = nil
        }
    }

    /// 拖拽落点按各块实测高累加（Web 口径；固定步距对
    /// 高块必错位）。行间隙 6 与 BlockRow 排版一致。
    func commitDrag() {
        guard let id = draggingId,
              let from = blocks.firstIndex(where: { $0.id == id })
        else { draggingId = nil; dragDy = 0; return }
        let gap: CGFloat = 6
        var to = from
        if dragDy > 0 {
            var acc: CGFloat = 0
            var j = from
            while j + 1 < blocks.count {
                let h = (blocks[j + 1].height > 0
                    ? blocks[j + 1].height : 40) + gap
                if dragDy > acc + h / 2 {
                    acc += h
                    j += 1
                    to = j
                } else { break }
            }
        } else if dragDy < 0 {
            var acc: CGFloat = 0
            var j = from
            while j - 1 >= 0 {
                let h = (blocks[j - 1].height > 0
                    ? blocks[j - 1].height : 40) + gap
                if -dragDy > acc + h / 2 {
                    acc += h
                    j -= 1
                    to = j
                } else { break }
            }
        }
        // 双栏呈现时落点钳制在来源栏内（跨栏拖拽单列一
        // 步，未做）；单栏时不钳制。M-09：钳制只对
        // independent 成立——flow 分界是内容派生、无
        // 栏界可钳，旧与 independent 共用钳制令 flow
        // 拖拽被隐形栏界截断（Web move_block 无任何
        // 钳制）；与 dragShift 的栏界门同源同改。
        if columnsActive, twoPaneIndependent,
           blocks.count > 1 {
            let b = columnBoundaryIndex
            if from < b {
                to = min(to, b - 1)
            } else {
                to = max(to, b)
            }
        }
        // F-16 拖拽维护 layout 锚：重排前以现 layout
        // 记有效分界数（锚不存在则分界纯由内容决
        // 定、无锚可维护）；independent 锚在位时，
        // 重排后名单按新序以同一分界数切分重写、
        // mode 保留——否则窄屏休眠期跨锚拖拽令名
        // 单与新序脱钩、回宽屏时分界跳位（Web
        // move_block 拖拽维护同口径）。flow 不读不
        // 写 layout 分界，不在此列。
        let anchorMode = layout?["mode"] as? String
            ?? "independent"
        let anchorBoundary = layout.flatMap {
            Self.normalizeBoundary(blocks: blocks,
                                   layout: $0)
        }
        if to != from {
            pushHistory()
            let moved = blocks.remove(at: from)
            blocks.insert(moved, at: to)
            if anchorMode == "independent",
               let ab = anchorBoundary {
                let ids = blocks.map { $0.id }
                layout = ["version": 1,
                          "mode": anchorMode,
                          "left": Array(ids[..<ab]),
                          "right": Array(ids[ab...])]
                DiagLog.shared.log(.info,
                    "EDIT drag anchor maintained "
                    + "boundary=\(ab)")
            }
            scheduleSave()
        }
        draggingId = nil; dragDy = 0
    }

    // ── 单篇导出（Web 口径：MD/HTML/PDF 三路） ──
    private var pdfMaker: PdfMaker?

    private var exportBaseName: String {
        let t = title.trimmingCharacters(in: .whitespaces)
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = t.components(separatedBy: bad)
            .joined(separator: "_")
        return cleaned.isEmpty ? Lang.t("editor.untitled") : cleaned
    }

    func exportFile(format: String) -> URL? {
        let content = format == "md"
            ? ExportGen.markdown(title: title, blocks: blocks)
            : ExportGen.html(title: title, blocks: blocks)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "\(exportBaseName).\(format)")
        do {
            try content.write(to: url, atomically: true,
                              encoding: .utf8)
            DiagLog.shared.log(.info,
                "单篇导出 \(format) ok bytes="
                + "\(content.utf8.count) id=\(item.id)")
            return url
        } catch {
            DiagLog.shared.log(.error,
                "单篇导出 \(format) 失败: \(error)")
            return nil
        }
    }

    func exportPDF(completion: @escaping (URL?) -> Void) {
        let html = ExportGen.html(title: title, blocks: blocks)
        let maker = PdfMaker()
        pdfMaker = maker
        maker.make(html: html,
                   fileName: "\(exportBaseName).pdf") {
            [weak self] url in
            self?.pdfMaker = nil
            if url != nil {
                DiagLog.shared.log(.info,
                    "单篇导出 pdf ok id="
                    + "\(self?.item.id ?? "?")")
            } else {
                DiagLog.shared.log(.error,
                    "单篇导出 pdf 失败")
                ErrBadge.shared.addError(Lang.t("errbadge.pdf_failed"))
            }
            completion(url)
        }
    }
}

/// HTML → PDF（离屏 WKWebView + createPDF，原生等价路）。
final class PdfMaker: NSObject, WKNavigationDelegate {
    private var web: WKWebView?
    private var fileName = "export.pdf"
    private var done: ((URL?) -> Void)?

    func make(html: String, fileName: String,
              completion: @escaping (URL?) -> Void) {
        self.fileName = fileName
        done = completion
        let wv = WKWebView(frame: CGRect(
            x: 0, y: 0, width: 612, height: 792))
        wv.navigationDelegate = self
        web = wv
        wv.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ wv: WKWebView,
                 didFinish navigation: WKNavigation!) {
        wv.createPDF(configuration: WKPDFConfiguration()) {
            [weak self] result in
            guard let self else { return }
            var out: URL?
            if case .failure(let e) = result {
                // 失败原因本体记行（AUD-E-05③）：旧
                // 口径只回 nil，上层（exportPDF 的
                // completion 行）只知失败不知因。
                DiagLog.shared.log(.error,
                    "PDF make create failed: \(e)")
            }
            if case .success(let data) = result {
                let url = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(self.fileName)
                if (try? data.write(to: url)) != nil {
                    out = url
                }
            }
            self.web = nil
            self.done?(out)
            self.done = nil
        }
    }

    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        // 失败原因本体记行（AUD-E-05③），同 create
        // 失败面口径。
        DiagLog.shared.log(.error,
            "PDF make nav failed: \(error)")
        web = nil
        done?(nil)
        done = nil
    }
}

/// 导出生成（MD/HTML）：块集映射，行内标记转对应语法。
enum ExportGen {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func mdRuns(_ runs: [[String: Any]]) -> String {
        runs.map { r in
            var t = r["text"] as? String ?? ""
            if r["code"] as? Bool == true { t = "`\(t)`" }
            if r["bold"] as? Bool == true { t = "**\(t)**" }
            if r["italic"] as? Bool == true { t = "*\(t)*" }
            if r["strikethrough"] as? Bool == true {
                t = "~~\(t)~~"
            }
            if let u = r["_link"] as? String {
                t = "[\(t)](\(u))"
            }
            return t
        }.joined()
    }

    static func htmlRuns(_ runs: [[String: Any]]) -> String {
        runs.map { r in
            var t = esc(r["text"] as? String ?? "")
            if r["code"] as? Bool == true {
                t = "<code>\(t)</code>"
            }
            if r["bold"] as? Bool == true {
                t = "<strong>\(t)</strong>"
            }
            if r["italic"] as? Bool == true {
                t = "<em>\(t)</em>"
            }
            if r["underline"] as? Bool == true {
                t = "<u>\(t)</u>"
            }
            if r["strikethrough"] as? Bool == true {
                t = "<s>\(t)</s>"
            }
            if let u = r["_link"] as? String {
                t = "<a href=\"\(esc(u))\">\(t)</a>"
            }
            return t
        }.joined()
    }

    static func markdown(title: String,
                         blocks: [BlockState]) -> String {
        var out: [String] = []
        if !title.isEmpty { out.append("# \(title)") }
        for b in blocks {
            out.append(mdBlock(b))
        }
        return out.joined(separator: "\n\n")
    }

    private static func mdBlock(_ b: BlockState) -> String {
        let attrs = b.node["attrs"] as? [String: Any] ?? [:]
        switch b.type {
        case "heading":
            return String(repeating: "#", count: b.level + 1)
                + " " + mdRuns(b.runs)
        case "todo":
            return "- [\(b.checked ? "x" : " ")] "
                + mdRuns(b.runs)
        case "quote":
            return "> " + mdRuns(b.runs)
        case "callout":
            return "> [!\(b.calloutVariant.uppercased())] "
                + mdRuns(b.runs)
        case "codeBlock":
            return "```\n\(b.text)\n```"
        case "divider":
            return "---"
        case "image":
            if let u = b.imageURL { return "![图片](\(u))" }
            if let f = b.fileId {
                return "![图片](attachment://\(f))"
            }
            return ""
        case "gallery":
            let items = attrs["items"] as? [[String: Any]]
                ?? []
            return items.map {
                if let u = $0["url"] as? String {
                    return "![图片](\(u))"
                }
                if let f = $0["fileId"] as? String {
                    return "![图片](attachment://\(f))"
                }
                return ""
            }.joined(separator: "\n")
        case "musicCard", "link-card":
            let meta = b.node["meta"] as? [String: Any] ?? [:]
            let t = (meta["title"] as? String) ?? b.type
            let u = (b.node["url"] as? String) ?? ""
            return "[\(t)](\(u))"
        case "video":
            let u = b.imageURL ?? ""
            return "[视频](\(u))"
        case "attachment":
            let name = (attrs["name"] as? String) ?? "附件"
            if let f = b.fileId {
                return "[\(name)](attachment://\(f))"
            }
            return name
        case "imgTextCard", "imageTextRow":
            var s = ""
            if let f = b.fileId {
                s = "![图片](attachment://\(f))\n\n"
            } else if let u = b.imageURL {
                s = "![图片](\(u))\n\n"
            }
            return s + b.text
        case "bulleted-list", "numbered-list":
            let kids = b.node["children"] as? [[String: Any]]
                ?? []
            return kids.enumerated().map { i, k in
                let sub = k["children"] as? [[String: Any]]
                    ?? []
                let t = sub.compactMap {
                    $0["text"] as? String
                }.joined()
                return b.type == "numbered-list"
                    ? "\(i + 1). \(t)" : "- \(t)"
            }.joined(separator: "\n")
        default:
            return mdRuns(b.runs)
        }
    }

    static func html(title: String,
                     blocks: [BlockState]) -> String {
        var body: [String] = []
        if !title.isEmpty {
            body.append("<h1>\(esc(title))</h1>")
        }
        for b in blocks {
            body.append(htmlBlock(b))
        }
        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(title))</title>
        <style>body{font-family:-apple-system,'PingFang SC',sans-serif;line-height:1.75;max-width:720px;margin:24px auto;padding:0 16px;color:#1a1a1a}img{max-width:100%}blockquote{border-left:3px solid #005bbb62;margin:0;padding:4px 14px;background:#00000006}code{background:#0000000d;padding:1px 5px;border-radius:5px}pre code{display:block;padding:12px;overflow:auto}</style>
        </head><body>
        \(body.joined(separator: "\n"))
        </body></html>
        """
    }

    private static func htmlBlock(_ b: BlockState) -> String {
        let attrs = b.node["attrs"] as? [String: Any] ?? [:]
        switch b.type {
        case "heading":
            return "<h\(b.level + 1)>"
                + htmlRuns(b.runs) + "</h\(b.level + 1)>"
        case "todo":
            return "<p>\(b.checked ? "☑" : "☐") "
                + htmlRuns(b.runs) + "</p>"
        case "quote":
            return "<blockquote>" + htmlRuns(b.runs)
                + "</blockquote>"
        case "callout":
            return "<blockquote><strong>"
                + b.calloutTitle + "</strong><br>"
                + htmlRuns(b.runs) + "</blockquote>"
        case "codeBlock":
            return "<pre><code>" + esc(b.text)
                + "</code></pre>"
        case "divider":
            return "<hr>"
        case "image":
            if let u = b.imageURL {
                return "<p><img src=\"\(esc(u))\"></p>"
            }
            if let f = b.fileId {
                return "<p><img src=\"attachment://\(f)\"></p>"
            }
            return ""
        case "gallery":
            let items = attrs["items"] as? [[String: Any]]
                ?? []
            return items.map {
                if let u = $0["url"] as? String {
                    return "<p><img src=\"\(esc(u))\"></p>"
                }
                if let f = $0["fileId"] as? String {
                    return "<p><img src=\"attachment://\(f)\"></p>"
                }
                return ""
            }.joined(separator: "\n")
        case "musicCard", "link-card":
            let meta = b.node["meta"] as? [String: Any] ?? [:]
            let t = (meta["title"] as? String) ?? b.type
            let u = (b.node["url"] as? String) ?? ""
            return "<p><a href=\"\(esc(u))\">\(esc(t))</a></p>"
        case "video":
            let u = b.imageURL ?? ""
            return "<p><a href=\"\(esc(u))\">视频</a></p>"
        case "attachment":
            let name = (attrs["name"] as? String) ?? "附件"
            return "<p>📎 \(esc(name))</p>"
        case "imgTextCard", "imageTextRow":
            var s = ""
            if let f = b.fileId {
                s = "<p><img src=\"attachment://\(f)\"></p>"
            } else if let u = b.imageURL {
                s = "<p><img src=\"\(esc(u))\"></p>"
            }
            return s + "<p>" + esc(b.text) + "</p>"
        case "bulleted-list", "numbered-list":
            let kids = b.node["children"] as? [[String: Any]]
                ?? []
            let tag = b.type == "numbered-list" ? "ol" : "ul"
            let lis = kids.map { k in
                let sub = k["children"] as? [[String: Any]]
                    ?? []
                let t = sub.compactMap {
                    $0["text"] as? String
                }.joined()
                return "<li>" + esc(t) + "</li>"
            }.joined()
            return "<\(tag)>\(lis)</\(tag)>"
        default:
            return "<p>" + htmlRuns(b.runs) + "</p>"
        }
    }
}

/// 块拖拽按压引擎（DragPressEngine / DragPressAnchor）
/// 已独立至 MomentDrag.swift（0.9.47 第二轮根治：滚动
/// 视图级单识别器全程所有，旧 DragPickupInstaller 整段
/// 删除、无兼容残留）。

/// 卡编辑态的选图/输链接面打包（图库加图多选、图库
/// 换图单选、音乐卡 URL 编辑）：独立 modifier 承载，
/// 避免 EditorView body 修饰链类型检查超时。
struct CardEditSheets: ViewModifier {
    @ObservedObject var editor: EditorModel
    @ObservedObject var ui: EditorView.EditorUI

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { editor.showGalleryAddPicker },
                set: { editor.showGalleryAddPicker = $0 })) {
                MultiPhotoPicker { picked in
                    guard let bid = editor.galleryPickBlockId
                    else { return }
                    var fids: [String] = []
                    for (data, pname) in picked {
                        let fid = "att-" + UUID().uuidString
                            .prefix(12).lowercased()
                        guard editor.library.putAttachment(
                            fid, data, name: pname) else {
                            DiagLog.shared.log(.error,
                                "图库加图未成（附件写入失败）"
                                + "fid=\(fid)")
                            continue
                        }
                        fids.append(fid)
                    }
                    editor.applyGalleryAdd(blockId: bid,
                                           fileIds: fids)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { editor.showGalleryReplacePicker },
                set: { editor.showGalleryReplacePicker = $0 })) {
                PhotoPicker { data, pname in
                    guard let bid = editor.galleryPickBlockId,
                          let ix = editor.galleryReplaceIndex
                    else { return }
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    guard editor.library.putAttachment(
                        fid, data, name: pname) else {
                        DiagLog.shared.log(.error,
                            "图库换图未生效（附件写入失败）"
                            + "fid=\(fid)")
                        return
                    }
                    editor.applyGalleryReplace(blockId: bid,
                                               index: ix,
                                               fileId: fid)
                }
                .ignoresSafeArea()
            }
            .alert(Lang.t("sheet.edit_link"), isPresented: Binding(
                get: { ui.musicEditBlockId != nil },
                set: { if !$0 { ui.musicEditBlockId = nil } })) {
                TextField("https://…", text: Binding(
                    get: { ui.musicURLDraft },
                    set: { ui.musicURLDraft = $0 }))
                Button(Lang.t("action.cancel"), role: .cancel) {}
                Button(Lang.t("action.save")) {
                    guard let bid = ui.musicEditBlockId,
                          let b = editor.blocks.first(
                            where: { $0.id == bid })
                    else { return }
                    let url = ui.musicURLDraft
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines)
                    guard !url.isEmpty else { return }
                    editor.pushHistory()
                    var n = b.node
                    n["url"] = url
                    n["meta"] = nil
                    n["status"] = "loading"
                    b.node = n
                    b.nodeVersion += 1
                    editor.scheduleSave()
                    editor.startResolveCard(b)
                    DiagLog.shared.log(.info,
                        "EDIT music url set \(bid)")
                }
            }
    }
}

struct BlockRow: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var block: BlockState
    // M30：系统「减弱动态效果」时拖拽类动画降级为
    // 瞬时（Web 全局熔断口径的原生对应）。
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 字形封顶同源度量（impl_dt_layout_resilience）。
    @ScaledMetric(relativeTo: .title2)
    private var f22: CGFloat = 22
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15

    /// 卡片类块（Web CARD_MENU_TYPES）：0.9.49 起与
    /// 文本块同走按压引擎拾起（Web pickup 对全部块
    /// 单元一视同仁、原子块全可拖、卡菜单骑拾起；
    /// 用户 2026-11-27 纠正口径）——本判定现只决定
    /// 拾起后骑哪套菜单（卡菜单 cardMenuBlockId vs
    /// 类型转换菜单 blockMenuBlockId），不再决定武
    /// 装与否。此前「卡片不参与拖拽、菜单优先」是
    /// 0.9.19 的范围裁剪、非 Web 口径，已废；其独
    /// 立 SwiftUI 长按（CardMenuGesture）同轮退役。
    /// 成员集 2026-11-28 起含原生扩展 codeBlock/
    /// embedCard（impl_card_guard_unify）：同集另经
    /// BlockState.isStructuralAtomic 驱动合并守卫与
    /// 选中描边，成员的删除/结构溶解自此只经本菜单。
    private var isCardType: Bool {
        EditorModel.cardMenuTypes.contains(block.type)
    }

    // 行面口径（Web editor.css）：常态无底无框；引用 =
    // 淡底+3px 蓝竖条+10 圆角，提示 = 语义淡底+12 圆角；
    // 块操作收进长按菜单（与原版一致，常驻按钮已撤）。
    var body: some View {
        // 类型转换/删除菜单已改由按压引擎拾起呈现
        // （blockMenuLayer，0.9.47）：旧 .contextMenu 的
        // UIContextMenuInteraction 自带行级长按识别、
        // 与拾起同抢一个触点，是第二轮根治清零的行级
        // 竞争消费者之一，不再回潮（verify [14] 锁）。
        rowMain
            // 自检驱动注册（U3）：块行面——动作即
            // DragPressAnchor 四回调的同一组方法
            // （dragPickup/dragMove/dragDrop/
            // dragCancel，S3 单一来源）；状态回行
            // 拖拽偏移实值（rowDragOffset 与渲染同
            // 源）与卡面通道读数。几何判读走
            // BlockState 量测通道（探针），本面
            // frameInWindow 只作在位标记。
            .background(UITestAnchor(
                providesFrame: false) {
                UITestSurfaceEntry(
                    id: "editor.blockRow",
                    kind: "block",
                    instance: block.id,
                    actions: [
                        "pickup": { _ in dragPickup() },
                        "drag": { d in
                            dragMove(CGFloat(d ?? 0))
                        },
                        "drop": { _ in dragDrop() },
                        "cancel": { _ in dragCancel() },
                    ],
                    state: [
                        "type": { block.type },
                        "dragging": {
                            editor.draggingId == block.id
                                ? "true" : "false"
                        },
                        "dragOffset": {
                            "\(rowDragOffset)"
                        },
                        "menuShown": {
                            (editor.cardMenuBlockId
                                == block.id
                             || editor.blockMenuBlockId
                                == block.id)
                                ? "true" : "false"
                        },
                        "faceRadius": {
                            "\(block.faceRadius)"
                        },
                    ])
            })
    }

    private var rowMain: some View {
        // 间距恒 0（2026-11-27 留白根治，fix_lift_
        // spacing.md）：HStack 的 spacing 在每个相邻
        // 子视图间都生效——尾随 Spacer 之前再吃一口，
        // 使内容槽恒比行盒窄 8（todo 10）、且只亏在
        // 右侧：卡面右缘内缩（截图二实测左 16.3 / 右
        // 25pt）、拾起框右间隙 = 4 + 8（截图一实测
        // ≈11.5pt、余三边 4）。语义间隙一律就地挂在
        // 所属元素上（todo 文侧 leading 10、引用条
        // 改面缘 overlay），内容槽恒 = 行盒全宽、卡
        // 面与行盒同源（Web 单元 width:100% 口径）。
        HStack(alignment: block.type == "todo"
                ? .center : .top,
               spacing: 0) {
            if block.type == "todo" {
                Button {
                    editor.toggleTodoChecked(block)
                } label: {
                    Image(systemName: block.checked
                        ? "checkmark.circle.fill"
                        : "circle")
                        // 字形封顶（布局韧性批）：title2
                        // 字形在大字号档达 ≈69pt、溢出
                        // 44 命中槽压正文——封顶 30（槽
                        // 内余量 7/侧），命中域 44 与默
                        // 认档逐值不变。
                        .font(.system(size: min(f22, 30)))
                        .foregroundStyle(block.checked
                            ? T.checkChecked : T.checkBorder)
                        // M27：勾选过渡 0.15s（Web
                        // checkbox transition 口径）。
                        .animation(.easeInOut(duration: 0.15),
                                   value: block.checked)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // 文起点对齐 Web：行左 padding 8 + 点击
                // 域 44 + gap 10 = 62（线 1 #13；原先
                // trailing −22 压缩使文起点落在 30）。
            }
            if block.type == "image" {
                ImageBlockView(block: block,
                               library: editor.library,
                               lifted: editor.draggingId
                                   == block.id)
                    .padding(.horizontal,
                             editor.columnsActive ? 0 : 36)
                    // 卡面通道（U2）：image 面在行内
                    // （内缩后卡槽），由本分支面
                    // GeometryReader 回报四值；半径
                    // 在子视图 LiftFrame 调用点、行
                    // 级无单值——faceRadius 恒记
                    // −1（面在子视图哨兵）。
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let f = geo.frame(
                                    in: .named("editorScroll"))
                                block.faceMinX = f.minX
                                block.faceMinY = f.minY
                                block.faceW = geo.size.width
                                block.faceH = geo.size.height
                                block.faceRadius = -1
                            }
                            .onChange(of: geo.frame(
                                in: .named("editorScroll")).minX) { x in
                                block.faceMinX = x
                            }
                            .onChange(of: geo.frame(
                                in: .named("editorScroll")).minY) { y in
                                block.faceMinY = y
                            }
                            .onChange(of: geo.size.width) { w in
                                block.faceW = w
                            }
                            .onChange(of: geo.size.height) { h in
                                block.faceH = h
                            }
                    })
                    .onTapGesture {
                        if editor.cardEditBlockId == block.id {
                            // 卡编辑态点图 = 换图（Web
                            // cardPick kind=set 同口径）。
                            editor.replaceImageBlockId = block.id
                            editor.showReplacePicker = true
                        } else if block.fileId == nil
                            && block.imageURL == nil {
                            editor.replaceImageBlockId = block.id
                            editor.showReplacePicker = true
                        } else {
                            editor.presentImagePage(
                                fileId: block.fileId,
                                urlString: block.imageURL,
                                name: block.node["name"]
                                    as? String)
                        }
                    }
            } else if block.type == "gallery" {
                // Web 口径：图库左右内缩 36（与图片块
                // 同）；宽屏（双栏）下 Web 取消内缩。
                GalleryBlockView(block: block, editor: editor)
                    .padding(.horizontal,
                             editor.columnsActive ? 0 : 36)
                    // 卡面通道（U2）：gallery 面同
                    // image 分支口径（内缩后格网槽、
                    // 半径在子视图、faceRadius = −1）。
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                let f = geo.frame(
                                    in: .named("editorScroll"))
                                block.faceMinX = f.minX
                                block.faceMinY = f.minY
                                block.faceW = geo.size.width
                                block.faceH = geo.size.height
                                block.faceRadius = -1
                            }
                            .onChange(of: geo.frame(
                                in: .named("editorScroll")).minX) { x in
                                block.faceMinX = x
                            }
                            .onChange(of: geo.frame(
                                in: .named("editorScroll")).minY) { y in
                                block.faceMinY = y
                            }
                            .onChange(of: geo.size.width) { w in
                                block.faceW = w
                            }
                            .onChange(of: geo.size.height) { h in
                                block.faceH = h
                            }
                    })
            } else if block.type == "musicCard",
                      block.cardFace == .inputPill {
                MusicPillView(editor: editor, block: block)
            } else if block.type == "musicCard"
                        || block.type == "link-card" {
                CardBlockView(block: block,
                              editor: editor)
            } else if block.type == "video" {
                VideoBlockView(block: block,
                               library: editor.library)
            } else if block.type == "attachment" {
                AttachmentBlockView(block: block,
                                    editor: editor)
            } else if block.type == "imgTextCard"
                        || block.type == "imageTextRow" {
                ImgTextBlockView(block: block, editor: editor)
            } else if block.type == "divider" {
                // 渐变线（Web hr 口径，线 1 #25）：1px
                // 透明→边色→透明，上下各 16。
                LinearGradient(
                    colors: [.clear, T.borderSoft, .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.vertical, 16)
            } else if block.type == "paragraph",
                      editor.editingBlockId != block.id,
                      editor.focusBlockId != block.id,
                      editor.mdKind(for: block) != "none" {
                // MD 源段落失焦预览（Web 口径）：未编辑时
                // 渲染解析树，点按回源码、光标落末尾。
                MdPreviewView(editor: editor, block: block)
            } else if block.type == "callout" {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: block.calloutIcon)
                            .font(.system(size: f18,
                                          weight: .semibold))
                            .foregroundStyle(
                                block.calloutAccent)
                        Text(block.calloutTitle)
                            .font(.system(size: f15, weight: .bold))
                            .foregroundStyle(T.textMain)
                    }
                    BlockTextView(block: block, editor: editor) {
                        editor.scheduleSave()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if block.isList {
                ListBlockView(block: block, editor: editor)
            } else if block.isText {
                // 引用左条不在行内占位（旧行内条 + 间
                // 距使文内缩 = 14 + 3 + 8 = 25，Web 与
                // MD 引用块均为 17）：条改挂面左缘
                // overlay（见修饰链），文内缩由行
                // leading padding 17 一处给出
                // （fix_lift_spacing.md）。
                VStack(alignment: .leading, spacing: 0) {
                    BlockTextView(block: block, editor: editor) {
                        editor.scheduleSave()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if block.type == "heading"
                        && block.level == 1 {
                        Rectangle()
                            .fill(T.borderSoft)
                            .frame(height: 1)
                            .padding(.top, 7)
                    }
                }
                .padding(.top, block.type == "heading"
                    ? (block.level == 1 ? 24
                        : block.level == 2 ? 20 : 18) : 0)
                // todo 勾选钮与文的间隙 10 就地挂文侧
                // （旧 HStack spacing 10 兼充尾随幻影
                // 间距，已随 spacing 恒 0 退役；文起点
                // 仍 = 8 + 44 + 10 = 62 不变）。
                .padding(.leading,
                         block.type == "todo" ? 10 : 0)
            } else if block.type == "embedCard" {
                // embedCard 无专门卡渲染（原版只读渲染
                // 与 Rust Web 均为兜底段落）：显示
                // children 文本拼接，不露开发文案。
                Text(block.text)
                    .font(.system(size: f14))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                // 未知块降级呈现（E4/F-17，Web audit2
                // 定案口径：降级纯文本 + log_once）：类
                // 型标识小字 + 正文纯文本保全呈现，不露
                // 开发文案、不吞正文。再保存保真由数据
                // 层承担（flushedNode 对未知块原样透
                // 传），本支只改呈现、不动 node。
                VStack(alignment: .leading, spacing: 4) {
                    Text(block.type)
                        .font(.system(size: f11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !block.text.isEmpty {
                        Text(block.text)
                            .font(.system(size: f14))
                            .foregroundStyle(T.textMain)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                    }
                }
                .padding(.vertical, 6)
                .onAppear {
                    DiagLog.shared.logOnce(
                        "unknown-block:\(block.type)",
                        .info,
                        "EDIT unknown block "
                        + "type=\(block.type) "
                        + "chars=\(block.text.count)")
                }
            }
            Spacer(minLength: 0)
        }
        // 左右分开给：引用文内缩对 Web blockquote
        // （左 = 左条 3 + padding 14 = 17、右 = 14，
        // 与 MD 引用块同口径，fix_lift_spacing.md）；
        // 余型左右同值、与旧 .horizontal 等价。
        .padding(.leading,
                 block.type == "quote" ? 17
                    : block.type == "callout"
                        || block.type == "codeBlock"
                        ? 14
                        : block.type == "todo" ? 8 : 0)
        .padding(.trailing,
                 block.type == "callout" || block.type == "quote"
                    || block.type == "codeBlock"
                    ? 14
                    : block.type == "todo" ? 8 : 0)
        .padding(.vertical, block.type == "callout" ? 12
                    : block.type == "quote" ? 10
                    : block.type == "codeBlock" ? 12 : 0)
        .background {
            // 跨块选区行面高亮（F-09，Web ::high-
            // light(mn-xsel) 同值 T.xselHighlight）：
            // 仅端点容器之间的原子行整行着色（Web
            // 原子单元整块着色同面）；文本行走段内
            // 分段着色（BlockTextView 属性层，二
            // 期）不在此面。本层先于行底色落 = 绘
            // 在底色之上、字形之下（CSS Highlight
            // 层序同构）；覆盖判定单点在桥接层
            // xselRowCovered。
            if editor.xselRowCovered(block) {
                RoundedRectangle(cornerRadius:
                    block.type == "quote"
                        ? Radius.quote : Radius.block)
                    .fill(T.xselHighlight)
            }
        }
        .background(rowBackground,
                    in: RoundedRectangle(cornerRadius:
                        block.type == "quote"
                            ? Radius.quote : Radius.block))
        .overlay {
            // 引用/提示/代码块三边 1px 描边（Web
            // --border-color，线 1 #16/#21/#24；引用左
            // 条挂面左缘 overlay，见下一层）。
            if block.type == "quote"
                || block.type == "callout"
                || block.type == "codeBlock" {
                RoundedRectangle(cornerRadius:
                    block.type == "quote"
                        ? Radius.quote : Radius.block)
                    .strokeBorder(T.borderSoft,
                                  lineWidth: 1)
            }
        }
        .overlay {
            // 原子块选中态描边（F-08，Web sel_block
            // 选中呈现的原生对应）：段首退格撞原子
            // 前驱置位、进入文本编辑/块被删即清（清
            // 除面在 EditorModel.selectedBlockId）。
            // 呈现分类与合并守卫同点（isStructural-
            // Atomic）：代码块被带入选中态同显描边。
            if editor.selectedBlockId == block.id,
               block.isStructuralAtomic {
                RoundedRectangle(
                    cornerRadius: Radius.block)
                    .strokeBorder(T.accent,
                                  lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            // 引用左条（Web blockquote border-left
            // 3px、MD 引用块同形态）：贴面左缘全高、
            // 不占行内位；文内缩 17 由行 leading
            // padding 给出（fix_lift_spacing.md）。
            if block.type == "quote" {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(T.quoteBar)
                    .frame(width: 3)
                    .allowsHitTesting(false)
            }
        }
        .background(GeometryReader { geo in
            // 行盒高回报（拖拽落点累加用）：全块型无
            // 条件写——height 的单点口径 = 行盒高（见
            // BlockState height 字段注；旧文本块由
            // UITextView 内容高喂入的双喂已废，内容
            // 高另记 contentH）。块顶位置一并回报
            // （斜杠面板锚定；非 Published 不触发重演算）。
            Color.clear
                .onAppear {
                    block.height = geo.size.height
                    block.rowW = geo.size.width
                    block.frameMinY = geo.frame(
                        in: .named("editorScroll")).minY
                    block.frameMinX = geo.frame(
                        in: .named("editorScroll")).minX
                    // 卡面通道（U2）：行级面（面 ≡
                    // 行槽）与行帧同点回报；面在子
                    // 视图的块型（liftFaceRadius ==
                    // nil）由行内分支面回报，不在此
                    // 写（哨兵 −1/未回报口径见
                    // BlockState face 字段注）。
                    if let r = liftFaceRadius {
                        block.faceMinX = block.frameMinX
                        block.faceMinY = block.frameMinY
                        block.faceW = geo.size.width
                        block.faceH = geo.size.height
                        block.faceRadius = r
                    }
                }
                .onChange(of: geo.size.height) { h in
                    block.height = h
                    if liftFaceRadius != nil {
                        block.faceH = h
                    }
                }
                .onChange(of: geo.size.width) { w in
                    block.rowW = w
                    if liftFaceRadius != nil {
                        block.faceW = w
                    }
                }
                .onChange(of: geo.frame(
                    in: .named("editorScroll")).minY) { y in
                    block.frameMinY = y
                    if liftFaceRadius != nil {
                        block.faceMinY = y
                    }
                }
                .onChange(of: geo.frame(
                    in: .named("editorScroll")).minX) { x in
                    block.frameMinX = x
                    if liftFaceRadius != nil {
                        block.faceMinX = x
                    }
                }
        })
        .background(DragPressAnchor(
            blockId: block.id,
            enabled: dragAllowed,
            onPickup: dragPickup,
            onDrag: dragMove,
            onDrop: dragDrop,
            onCancel: dragCancel))
        .background {
            // 拾起框（行级面）：面即行盒的块型在此挂
            // 框；image（有图）/gallery 的面在子视图内
            // （图本体/格网），行级不挂（见 liftFace）。
            if editor.draggingId == block.id,
               let r = liftFaceRadius {
                LiftFrame(faceRadius: r)
            }
        }
        // 拾起缩放（Web liftScaleFor 口径，用户
        // 2026-11-26 点名）：双轴按面尺寸算——每轴
        // scale = max((dim − 2×LIFT_INSET)/dim, 0.9)，
        // 缩小后四边恰让出与框外扩对位的 4；旧固定
        // 0.97 单轴为早期口径（小块几乎无感，用户实
        // 报「没感受到」）。量测缺失时回退 0.97。
        .scaleEffect(
            x: editor.draggingId == block.id
                ? liftScale(block.rowW) : 1,
            y: editor.draggingId == block.id
                ? liftScale(block.height) : 1)
        // M19：拾起/放下的缩放走 0.22s 弹簧过渡。
        // M30：减弱动态效果时降级瞬时。
        .animation(reduceMotion
                       ? nil
                       : .spring(response: 0.22,
                                 dampingFraction: 0.8),
                   value: editor.draggingId == block.id)
        .offset(y: rowDragOffset)
        // M20：兄弟让位以 Web 曲线 260ms 跟随（shift 为
        // 离散两值，动画即 .mn-shift 的 transform 过渡）。
        .animation(reduceMotion
                       ? nil
                       : .timingCurve(0.22, 0.61, 0.36, 1,
                                      duration: 0.26),
                   value: dragShift)
        .zIndex(editor.draggingId == block.id ? 1 : 0)
        .onDisappear {
            // 手势被系统取消时 onEnded 不触发：行卸载即
            // 复位拖拽态，防 draggingId 残留锁死全篇拾
            // 起（三线审计定案）；M-10 起与手势取消共
            // 用单点复位，拾起菜单一并清。
            editor.clearDragState(for: block.id)
        }
        .overlay {
            // 卡编辑态描边（Web .card-editing：2px
            // accent、offset 3；图文 radius 22、余 32）。
            if editor.cardEditBlockId == block.id {
                RoundedRectangle(cornerRadius:
                    block.type == "imgTextCard"
                        || block.type == "imageTextRow"
                        ? Radius.cardS : Radius.cardL)
                    .stroke(T.accent, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
        }
    }

    // ── 拖拽四入口（U3 单点化）──
    // DragPressAnchor 的四回调与自检驱动
    // editor.blockRow 面的四动作共用同一组方法
    // （S3 定案：驱动调识别器回调的同一组入口、
    // 不另起合成路径；合成 touches 喂识别器已
    // 否决）。方法体与抽取前行内闭包逐字等价
    // （行为等价重构，verify [68] 锁接线）。

    /// 拾起（原 onPickup 闭包体）。
    private func dragPickup() {
        if editor.draggingId == nil {
            editor.draggingId = block.id
            // M21 触觉：拾起中震（Web hapticTap
            // 在 iOS Safari 不可靠，原生补齐属
            // 等价更优）。
            UIImpactFeedbackGenerator(style: .medium)
                .impactOccurred()
            DiagLog.shared.log(.info,
                "DRAG pickup id=\(block.id) "
                + "type=\(block.type)")
            // 拾起收敛选区（0.9.49）：文本块拾
            // 起瞬间清本块选区/辞焦（Web pickup
            // 的 removeAllRanges 对应），防并行
            // 放开后选区长按的放大镜与拾起同屏。
            if editor.convergeSelectionOnPickup(
                blockId: block.id) {
                DiagLog.shared.log(.info,
                    "DRAG converge id=\(block.id)")
            }
            // 菜单骑拾起（Web 同构，0.9.47 起文
            // 本块如此、0.9.49 起卡片块同）：拾
            // 起即贴块弹出、转入拖动（>10px）
            // 自动收起、原地松手留存待点选。卡
            // 片块出卡菜单、余者出类型转换菜单
            // （旧 .contextMenu 项集的承接面）。
            if isCardType {
                editor.cardMenuBlockId = block.id
            } else {
                editor.blockMenuBlockId = block.id
            }
            DiagLog.shared.log(.info,
                "DRAG menu show id=\(block.id)")
        }
    }

    /// 跟手（原 onDrag 闭包体）。
    private func dragMove(_ dy: CGFloat) {
        if editor.draggingId == block.id {
            editor.dragDy = dy
            // 转入拖动即收起拾起菜单（Web
            // dragMove >10px 收菜单同口径，两
            // 套菜单同）。
            if abs(dy) > 10 {
                if editor.blockMenuBlockId
                    == block.id {
                    editor.blockMenuBlockId = nil
                }
                if editor.cardMenuBlockId
                    == block.id {
                    editor.cardMenuBlockId = nil
                }
            }
        }
    }

    /// 落位（原 onDrop 闭包体）。
    private func dragDrop() {
        if editor.draggingId == block.id {
            let dy = editor.dragDy
            editor.commitDrag()
            UIImpactFeedbackGenerator(style: .light)
                .impactOccurred()
            // M20 落位回弹：数据已重排，块在新
            // 位以拖尾偏移为起点弹簧归零。
            if dy != 0 {
                editor.settleId = block.id
                editor.settleDy = dy
                DispatchQueue.main.async {
                    if reduceMotion {
                        editor.settleDy = 0
                    } else {
                        withAnimation(.spring(
                            response: 0.26,
                            dampingFraction: 0.82)) {
                            editor.settleDy = 0
                        }
                    }
                }
                DispatchQueue.main
                    .asyncAfter(deadline: .now()
                        + 0.35) {
                    if editor.settleId == block.id {
                        editor.settleId = nil
                    }
                }
            }
        }
    }

    /// 取消（原 onCancel 闭包体）。
    private func dragCancel() {
        // M-10：与行卸载共用单点复位（拾起
        // 菜单一并清，防孤儿菜单）。
        editor.clearDragState(for: block.id)
    }

    /// 行纵向偏移三态：拖拽中跟手（dragDy）、刚落位
    /// 回弹中（settleDy）、兄弟让位（dragShift）。
    /// 拾起缩放单轴（Web liftScaleFor）：dim 方向缩
    /// 小后恰内收 LIFT_INSET×2，下限 0.9；量测未到
    /// （dim ≤ 0）回退旧值 0.97。
    private func liftScale(_ dim: CGFloat) -> CGFloat {
        dim > 0 ? max((dim - 8) / dim, 0.9) : 0.97
    }

    /// 行级拾起框的面半径（nil = 行级不挂框）。
    /// 0.9.52 根治：与各卡真实面同源——Radius 令牌
    /// + 与呈现分支同判据的状态派生，不再独立维护
    /// 第二张表。旧表三处漂移、拾起框与面不同心
    /// （用户点名的圆角不配）：图文/混排卡真面 22
    /// 误作 32、附件常态面 32 误作 22、音乐丸态真
    /// 面胶囊误作 32。对账见 fix_card_radius.md。
    /// image 有图时面是图本体（子视图内挂）、无图
    /// 占位面即行；gallery 面是格网（子视图内挂）。
    /// 补丁债偿还批二（A-2）：音乐/链接/附件三型
    /// 的状态派生已收口 CardFace 单点（呈现分发、
    /// 呈现本体、拾起面共消费同一面型值），旧音
    /// 乐/附件两份拾起面复制判别整删——本 switch
    /// 只剩类型令牌直给面与卡片三型的面型委托。
    private var liftFaceRadius: CGFloat? {
        switch block.type {
        case "quote": return Radius.quote
        case "callout", "codeBlock": return Radius.block
        case "imgTextCard", "imageTextRow":
            return Radius.cardS
        case "video": return Radius.cardS
        case "musicCard", "link-card", "attachment":
            return cardLiftRadius
        case "image":
            // 面恒在子视图内（图本体 cardS / 空占位
            // 面 cardL 各挂各的 LiftFrame），行级恒不
            // 出框（fix_lift_spacing.md）。
            return nil
        case "gallery": return nil
        default: return 0
        }
    }

    /// 卡片拾起面半径：面型经 CardFace.derive 单
    /// 点派生（与呈现同值），本点只把面型的半径
    /// 令牌绑到 Radius 数值（文件行面经 Radius.
    /// attachmentFile 与 AttachmentRow 行面同派
    /// 生：宽屏 cardS、常态 cardL）。
    private var cardLiftRadius: CGFloat {
        switch block.cardFace.radiusToken {
        case .pill: return Radius.pill
        case .cardL: return Radius.cardL
        case .attachmentFile:
            return Radius.attachmentFile(
                wide: editor.columnsActive)
        }
    }

    private var rowDragOffset: CGFloat {
        if editor.draggingId == block.id {
            return editor.dragDy
        }
        if editor.settleId == block.id {
            return editor.settleDy
        }
        return dragShift
    }

    /// M20 兄弟让位量：与 commitDrag 完全同源的落点
    /// 判定（实测高累加、过半换位、栏内钳制）——被拖
    /// 块落点越过本行时，本行反向让出被拖块全高。
    private var dragShift: CGFloat {
        guard let did = editor.draggingId,
              did != block.id,
              let from = editor.blocks.firstIndex(
                  where: { $0.id == did }),
              let me = editor.blocks.firstIndex(
                  where: { $0.id == block.id })
        else { return 0 }
        if editor.columnsActive,
           editor.twoPaneIndependent,
           editor.blocks.count > 1 {
            let b = editor.columnBoundaryIndex
            if (from < b) != (me < b) { return 0 }
        }
        let gap: CGFloat = 6
        func h(_ i: Int) -> CGFloat {
            (editor.blocks[i].height > 0
                ? editor.blocks[i].height : 40) + gap
        }
        let dragH = h(from)
        let dy = editor.dragDy
        if dy > 0, me > from {
            var acc: CGFloat = 0
            var j = from
            while j + 1 <= me {
                let step = h(j + 1)
                if dy > acc + step / 2 {
                    acc += step
                    j += 1
                } else { break }
            }
            return j >= me ? -dragH : 0
        }
        if dy < 0, me < from {
            var acc: CGFloat = 0
            var j = from
            while j - 1 >= me {
                let step = h(j - 1)
                if -dy > acc + step / 2 {
                    acc += step
                    j -= 1
                } else { break }
            }
            return j <= me ? dragH : 0
        }
        return 0
    }

    /// 行底恒为块自身常态底、拾起期不换（0.9.50 根
    /// 治，定案 fix_drag_pickup_visual.md）：Web
    /// .mn-lifted 不给单元加底/换底，拾起反馈由
    /// LiftFrame（视觉面 ⊕4 玻璃框）+ 缩放专责。
    /// 旧实现拾起期把行盒底换成 T.glassTint——面即
    /// 行盒的块型凭空多一层白板；image/gallery 的
    /// 面在行盒内内缩 36pt，白板左右各外凸 36pt，
    /// 即真机截图的「卡片拾起多出白色背景块」；引
    /// 用/提示/代码块则自身淡底被白板覆盖。三型同
    /// 根、一并清零（尾巴不留）。
    private var rowBackground: Color {
        switch block.type {
        case "callout": return block.calloutBg
        case "quote": return T.quoteBg
        case "codeBlock": return T.codeBg
        default: return .clear
        }
    }

    /// 武装口径（0.9.49，用户纠正 + Web 对账）：全部
    /// 块型一律武装（Web pickup 对 text / atomic /
    /// composite 单元一视同仁）；仅剩两类真守卫——
    /// 正在编辑的文本块长按 = 文本选择，永不拾起；
    /// 按钮类子视图由引擎 shouldReceive 先行排除。
    /// 卡片类 0.9.49 前恒 disarmed（0.9.19 范围裁
    /// 剪、非 Web 口径）已废。卡编辑态的行另行退场
    /// （F-14）：编辑的是卡内容而非块本身，且图库
    /// 瓦的拖拽排序同为长按起手——行保持武装则同
    /// 一触点双路竞抢（拾起史三轮根治的同型病灶），
    /// 退出编辑态（点卡外）即恢复武装。
    private var dragAllowed: Bool {
        !(block.isText && editor.editingBlockId == block.id)
            && editor.cardEditBlockId != block.id
    }

}

/// B-6：按 Unicode 标量取前缀（Web chars() 口径；
/// Swift 字素簇计数会让含 emoji 的标题截断点分叉）。
func scalarPrefix(_ s: String, _ n: Int) -> String {
    var out = ""
    out.unicodeScalars.append(
        contentsOf: s.unicodeScalars.prefix(n))
    return out
}

struct EditorView: View {
    @ObservedObject var editor: EditorModel
    var onOpenMemo: ((MemoItem) -> Void)? = nil
    /// 返回出口（0.9.50 呈现重构）：由转场宿主注入
    /// （pop 当前承载控制器）；页眉返回钮经
    /// EditorHeaderView.onBack 消费。旧形态靠环境
    /// dismiss 在 NavigationStack 内 pop，呈现改
    /// UIKit push 后改走此确定性出口。
    var onClose: (() -> Void)? = nil
    @StateObject private var ui = EditorUI()
    // 字体代次观察（fix_dynamic_type_follow）：系
    // 统类别变更时整树重演算，驱动 BlockTextView
    // 的 epoch 重刷与各 dynFont 量测重算——编辑器
    // 经 UIHostingController 承载，trait 转发不作
    // 唯一依赖，变更自 hub 的 UIKit 通知直达。
    @ObservedObject private var fontHub = FontHub.shared
    // 语言观察（AUD-C-04）：编辑器整树（含斜杠面板）
    // 随 LangStore 变更重演算，与其余页面同口径。
    @EnvironmentObject private var langStore: LangStore
    @Environment(\.dismiss) private var dismiss
    // M30：减弱动态效果时浮层进出场降级瞬时。
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @FocusState private var linkFieldFocused: Bool
    // 文字大小跟随系统（Dynamic Type 全量实装，
    // impl_dynamic_type_full）：无语义样式等值
    // 的字号走 ScaledMetric 相对缩放（基准值与
    // 既有定值逐值一致、默认档不变）。
    @ScaledMetric(relativeTo: .caption2)
    private var f10: CGFloat = 10
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .title)
    private var f28: CGFloat = 28
    @ScaledMetric(relativeTo: .title2)
    private var f22: CGFloat = 22
    @ScaledMetric(relativeTo: .title3)
    private var f19: CGFloat = 19
    // 字形封顶同源度量（impl_dt_layout_resilience）：
    // f20 供斜杠行/菜单行图标封顶（槽 24）、f17 供
    // 双栏行图标封顶（槽 24）、f34 为导出徽章盒
    // （随徽章字 caption2 同源缩放，默认档恒 34）；
    // 均默认档逐值不变。注：菜单/导出面板/双栏行
    // 实属 EditorView 作用域（DT 批 §6 归属口径）。
    @ScaledMetric(relativeTo: .title3)
    private var f20: CGFloat = 20
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17
    @ScaledMetric(relativeTo: .caption2)
    private var f34: CGFloat = 34
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2)
    private var f9: CGFloat = 9
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    // bgSheet/导出面板/菜单行的 subheadline 语
    // 义点喂点（fix_dynamic_type_follow 补声明）。
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15

    init(editor: EditorModel,
         onOpenMemo: ((MemoItem) -> Void)? = nil,
         onClose: (() -> Void)? = nil) {
        _editor = ObservedObject(wrappedValue: editor)
        self.onOpenMemo = onOpenMemo
        self.onClose = onClose
        // 首帧发布收敛（0.9.48，治 S2）：标题草稿与
        // 反向链接初值在 UI 状态对象诞生时种子化——
        // 旧实现等 EditorView.onAppear 后逐个回写
        // @Published，首帧平白多一轮全量 body。种子
        // 值与旧 onAppear 回写值同源同口径（标题直
        // 取、反链按标题查库），行为等价。
        let ui = EditorUI()
        ui.titleDraft = editor.title
        ui.backlinks = editor.library.backlinks(
            forTitle: editor.title,
            excludeId: editor.item.id)
        _ui = StateObject(wrappedValue: ui)
    }

    final class EditorUI: ObservableObject {
        @Published var showPhotoPicker = false
        @Published var showFilePicker = false
        @Published var showMenu = false
        @Published var showExport = false
        @Published var showBgSheet = false
        /// 背景底表出场态（Web .sheet-wrap.is-closing）：
        /// 关闭先播 220ms 出场（opacity→0 + 下移 20），
        /// 卸载时点才应用待生效颜色（原版 closeWithAnim
        /// 口径）；gen 防快速重入时旧回调误卸载新开的表。
        @Published var bgClosing = false
        var bgGen = 0
        var bgPendingApply = false
        var bgPendingColor: String? = nil
        /// 底安全区（body 的 GeometryReader 喂入，背景
        /// 底表悬浮间距与卡内底距按 Web 口径含 safe）。
        var safeBottom: CGFloat = 0
        /// 键盘可见边沿（编辑页完成胶囊的触发源）：
        /// 单点喂入 = UIKit 键盘通知（keyboardWill
        /// Show/Hide，本类 init 注册、deinit 注销，
        /// 写点收敛于 setKbVisible 一处）。旧喂入
        /// （safeBottom 边沿 sb > 0）已废弃并实证
        /// 为 0.9.56 真机回归根因：safeBottom 是含
        /// 设备安全区的量、静息值 = 主屏指示条高
        /// （Face ID 机型 34）而非 0——键盘升起边
        /// 沿能跨过阈值（展开正常），落下边沿只回
        /// 落到 34、永不跨回 0，本位自首次升起即
        /// 闩锁为真、胶囊永不回缩（点完成/滑动收
        /// 起/失焦各路同病，完成钮只是验出点）。
        /// 量测类消费（safeBottom/kbPad/CREATE 计
        /// 时）不共此病：其数值本身即语义、静息
        /// 34 正是口径。键盘可见性是事实、不是量
        /// 测——只许由平台通知喂入，不许再从任何
        /// 几何量派生（防回潮，F29-2 锁）。
        @Published var kbVisible = false
        private var kbTokens: [NSObjectProtocol] = []

        init() {
            let nc = NotificationCenter.default
            kbTokens.append(nc.addObserver(
                forName: UIResponder
                    .keyboardWillShowNotification,
                object: nil, queue: .main) { [weak self] n in
                let h = (n.userInfo?[
                    UIResponder
                        .keyboardFrameEndUserInfoKey]
                    as? CGRect)?.height ?? 0
                self?.setKbVisible(true, height: h)
            })
            kbTokens.append(nc.addObserver(
                forName: UIResponder
                    .keyboardWillHideNotification,
                object: nil, queue: .main) { [weak self] _ in
                self?.setKbVisible(false, height: 0)
            })
        }

        deinit {
            for t in kbTokens {
                NotificationCenter.default
                    .removeObserver(t)
            }
        }

        /// 键盘可见唯一写点：翻转才写并记行——桥
        /// 侧据此行与 donecapsule expand/collapse
        /// 行对读，可判「键盘事实 → 状态位 → 派
        /// 生 → 呈现」断在哪段。
        private func setKbVisible(_ visible: Bool,
                                  height: CGFloat) {
            guard kbVisible != visible else { return }
            kbVisible = visible
            DiagLog.shared.log(.info,
                "EDIT kb visible=\(visible ? 1 : 0) "
                + "src=notify h=\(Int(height))")
        }

        /// 发起背景底表关闭：只置出场态，实际卸载与
        /// 颜色生效由 EditorView 的 onChange 编排。
        func beginBgClose(apply: Bool, color: String?) {
            if bgClosing { return }
            bgGen += 1
            bgPendingApply = apply
            bgPendingColor = color
            bgClosing = true
        }
        @Published var showAttachChoice = false
        /// 音乐卡「编辑」即时动作（Web 口径：输 URL 重
        /// 解析，无持续编辑态）：EditorView 层 alert 承载。
        @Published var musicEditBlockId: String?
        @Published var musicURLDraft = ""
        @Published var titleDraft = ""
        @Published var linkError = false
        var viewW: CGFloat = 0
        var viewH: CGFloat = 0
        /// 标题编辑会话起点快照（Esc 还原源）。
        @Published var titleBase = ""
        @Published var shareURL: URL?
        @Published var linkDraft = ""
        @Published var backlinks: [MemoItem] = []
        @Published var showAvatarChoice = false
        @Published var showAvatarPicker = false
        /// 宽屏判定（Web 媒体查询口径）：(宽≥768 且 高≥600)
        /// 或 宽≥1100。由 EditorView 的 GeometryReader 喂入。
        @Published var wide = false
        /// 菜单面板整树已建（0.9.48 惰性构建）：隐藏
        /// 态不再每轮 body 重构整树（S2），转场落定
        /// 后预建或首次打开时即时建（见 EditorView）。
        @Published var menuBuilt = false
        /// 键盘落定底距（0.9.48，治 S3）：编辑区内容
        /// 对键盘安全区免疫、框高恒定，键盘遮挡量改
        /// 由内容底 padding 在落定时一次应用（去抖
        /// 80ms，动画期不逐帧重排）；落定值与旧口径
        /// （安全区逐帧收缩框高）的稳态避让量一致。
        @Published var kbPad: CGFloat = 0
        private var kbPadWork: DispatchWorkItem?
        func settleKbPad(_ sb: CGFloat) {
            kbPadWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.kbPad != sb else {
                    return
                }
                self.kbPad = sb
            }
            kbPadWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.08, execute: work)
        }
        /// 斜杠/链接面板实测高（呈现处 onGeometryChange
        /// 回写）：纵向锚按实测高定顶边，不用估高定中
        /// 心（线 2 #52）；0 = 尚未量得，首帧走构成估高。
        @Published var slashPanelH: CGFloat = 0
        /// 斜杠面板限高（cap）回写（U2 P3 扩展）：
        /// slashLayer 以与渲染同一 maxH 公式在既有
        /// onGeometryChange 量测点同点回写，供
        /// slash_panel 探针三值对读（contentH/
        /// renderedH = slashPanelH 实测回写、cap =
        /// 本值）；探针侧不重算公式，防双轨漂移。
        @Published var slashPanelMaxH: CGFloat = 0
        /// ••• 菜单内容实测高（面板内 VStack 的
        /// onGeometryChange 回写）：面板高 = 内容高
        /// （上限沿旧 cap）——旧实现 ScrollView 在
        /// ZStack 里被同级 Color.clear 撑到 cap、
        /// 内容悬空（截图四，fix_lift_spacing.md）；
        /// 0 = 尚未量得，首帧走构成估高。
        @Published var menuPanelH: CGFloat = 0
        /// 背景底表实测内容高（与 menuPanelH 同机制，
        /// impl_dt_layout_resilience）：0 = 未量得，
        /// 首帧走构成估高；帧高 = min(实测， 视口 − 28），
        /// 超出内滚——矮高 × 大字号组合下底表不再顶出屏外。
        @Published var bgSheetH: CGFloat = 0
        /// 导出面板实测内容高（同 bgSheetH 机制）：
        /// 帧高 = min(实测, 视口 − 67)，超高内滚；
        /// 默认档内容恒低于上限、呈现逐值不变。
        @Published var exportPanelH: CGFloat = 0
        /// ••• 菜单面板帧（window 坐标，面板呈现
        /// 处 GeometryReader 回写，非 @Published
        /// 量测通道，与 viewW/viewH 同纪律）：自
        /// 检驱动 menuPanel 面的 frame/renderedH
        /// 来源（U1）。
        var menuPanelFrame: CGRect? = nil
    }

    // 编辑页口径（Web .detail/.editor-fab/.editor-title-dock）：
    // 悬浮玻璃圆钮（左返回/右更多，46px，top=安全区+7）+
    // 居中标题坞（72 头像圆 + 66 高标题胶囊，标题 14/600
    // 居中、副行 10px 日期·字数）；正文上距 155 口径。
    var body: some View {
        // CREATE 量测：body 轮数（S2），仅新建回合在位
        // 时计数，普通打开零开销（guard 即返回）。
        editor.noteBodyPass()
        return ZStack(alignment: .top) {
            // 内容层对键盘安全区免疫（0.9.48，治 S3）：
            // 滚动框高不随键盘动画逐帧变，遮挡量改由
            // 内容底 padding 落定后一次应用（ui.kbPad）。
            contentArea
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onTapGesture {
                    // 卡编辑态：点按任意处先退出（Web
                    // 点卡外退出编辑态的近似——容器级
                    // tap 与子点按共存触发，编辑卡图区
                    // 的换图动作已先行置位、不受影响）。
                    if editor.cardEditBlockId != nil {
                        editor.exitCardEdit(via: "tap")
                    }
                }
            EditorHeaderView(editor: editor, ui: ui,
                             scroll: editor.scrollState,
                             onBack: onClose)
            if editor.slashBlockId != nil {
                slashLayer
            }
            if editor.cardMenuBlockId != nil {
                cardMenuLayer
                    .transition(.opacity)
            }
            if editor.blockMenuBlockId != nil {
                blockMenuLayer
                    .transition(.opacity)
            }
            // ••• 菜单进出场（M13）：右上锚点 scale 0.92 +
            // 上移 10 + 淡入，220ms 弹簧；常驻挂载、隐藏
            // 时禁命中（Web 关闭播满再卸载的等价处理）。
            // 0.9.48 惰性构建（治 S2）：整树（ScrollView +
            // 菜单项）在 ui.menuBuilt 前不构建——旧实现隐
            // 藏态仍每轮 body 全量重构。预建时点 = 转场
            // 落定事件（settleTick，偿还批一 A-7 改挂，
            // 见 onAppear/onChange），窗内抢先打开由
            // showMenu 的 onChange 兜底即时建（首开无进
            // 场动画、其后与旧口径一致）。
            if ui.menuBuilt {
                menuPanel
                    .opacity(ui.showMenu ? 1 : 0)
                    .scaleEffect(ui.showMenu ? 1 : 0.92,
                                 anchor: .topTrailing)
                    .offset(y: ui.showMenu ? 0 : -10)
                    .allowsHitTesting(ui.showMenu)
                    .animation(.spring(response: 0.22,
                                       dampingFraction: 0.82),
                               value: ui.showMenu)
            }
            // 背景色浮动底表（Web .sheet-wrap + .bg-sheet
            // 全形态）：悬浮卡（左右 14、底 = 安全区+14、
            // 全角 radius 28、上限 600 居中）+ 进出场
            // （opacity 200ms / 下移 20px + 250ms 弹簧
            // timingCurve(0.34,1.56,0.64,1)，出场 220ms
            // 后卸载且颜色在卸载时才生效）。不用系统
            // sheet（detent 几何两度翻车）、不用贴底全
            // 宽（那是上版自创形态、且丢了动画）。
            if ui.showBgSheet {
                GeometryReader { geo in
                    ZStack(alignment: .bottom) {
                        Color.clear
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ui.beginBgClose(
                                    apply: false, color: nil)
                            }
                        bgSheet
                            .frame(maxWidth: 600)
                            .padding(.horizontal, 14)
                            .padding(.bottom,
                                     geo.safeAreaInsets.bottom
                                        + 14)
                            .offset(y: ui.bgClosing ? 20 : 0)
                            .opacity(ui.bgClosing ? 0 : 1)
                            .animation(reduceMotion
                                           ? nil
                                           : .timingCurve(
                                               0.34, 1.56, 0.64, 1,
                                               duration: 0.25),
                                       value: ui.bgClosing)
                    }
                }
                .onAppear { ui.bgClosing = false }
            }
        }
        // 自检驱动注册（U1）：••• 菜单面锚点挂编
        // 辑器根（编辑器在位期间恒在层级）——
        // open/close 与页眉钮 toggle 同写
        // ui.showMenu 一个状态位（显式两向版），
        // frame 读 menuPanelFrame 量测通道。
        .background(UITestAnchor(providesFrame: true) {
            UITestSurfaceEntry(
                id: "editor.menuPanel", kind: "panel",
                instance: "-",
                frameInWindow: { ui.menuPanelFrame },
                actions: [
                    "open": { _ in
                        ui.showMenu = true
                    },
                    "close": { _ in
                        ui.showMenu = false
                    },
                ],
                state: [
                    "open": {
                        ui.showMenu ? "true" : "false"
                    },
                    "renderedH": {
                        ui.menuPanelFrame.map {
                            "\($0.height)"
                        } ?? ""
                    },
                    "contentH": { "\(ui.menuPanelH)" },
                    "capped": {
                        ui.menuPanelH
                            > max(200, ui.viewH - 67)
                            ? "true" : "false"
                    },
                ])
        })
        // 自检驱动注册（U4a）：斜杠面板面挂编辑器
        // 根（恒在层级，面板未开时 open=false 可
        // 读）——状态直读 EditorModel 斜杠三位
        // （slashBlockId/slashQuery/slashSel），选
        // 中命令由 SlashCmds.rowCommands 单源派
        // 生；动作走 slashMoveSel/slashApply-
        // Selected 具名入口（与键盘导航/回车执行
        // 同体），close 为模型 close() 同写（直
        // 置 slashBlockId=nil）。
        .background(UITestAnchor(providesFrame: true) {
            UITestSurfaceEntry(
                id: "editor.slashPanel", kind: "panel",
                instance: "-",
                actions: [
                    "applySelected": { _ in
                        editor.slashApplySelected()
                    },
                    "moveSel": { d in
                        editor.slashMoveSel(
                            Int(d ?? 1))
                    },
                    "close": { _ in
                        editor.slashBlockId = nil
                    },
                ],
                state: [
                    "open": {
                        editor.slashBlockId != nil
                            ? "true" : "false"
                    },
                    "query": { editor.slashQuery },
                    "sel": { "\(editor.slashSel)" },
                    "count": {
                        "\(SlashCmds.rowCommands(editor.slashQuery).count)"
                    },
                    "selAct": {
                        let cmds = SlashCmds
                            .rowCommands(editor.slashQuery)
                        guard !cmds.isEmpty else {
                            return ""
                        }
                        let i = min(max(editor.slashSel, 0),
                                    cmds.count - 1)
                        return cmds[i].act
                    },
                    // U2 P3 扩展三值（EDT-36）：
                    // panelH = 实测回写（内容/实高
                    // 同值口径见探针注）、panelMaxH
                    // = cap 同点回写。
                    "panelH": { "\(ui.slashPanelH)" },
                    "panelMaxH": {
                        "\(ui.slashPanelMaxH)"
                    },
                ])
        })
        .onChange(of: ui.showMenu) { open in
            // 菜单惰性构建的抢先兜底：预建时点（转场
            // 落定）未到就打开，立即建整树。
            if open && !ui.menuBuilt { ui.menuBuilt = true }
        }
        .onChange(of: editor.settleTick) { _ in
            // 菜单预建的落定触发面（A-7）：转场落定
            // 拍建整树，此后稳态打开带进出场动画；
            // 落定前打开由上方 showMenu 兜底即时建。
            if !ui.menuBuilt { ui.menuBuilt = true }
        }
        .onChange(of: ui.bgClosing) { closing in
            // 出场编排：220ms 后（gen 仍有效且仍在出场
            // 态）才应用待生效颜色并卸载底表。
            guard closing else { return }
            let gen = ui.bgGen
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.22) {
                guard ui.bgGen == gen, ui.bgClosing else {
                    return
                }
                if ui.bgPendingApply {
                    editor.setBgColor(ui.bgPendingColor)
                }
                ui.showBgSheet = false
                ui.bgClosing = false
            }
        }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    syncWide(geo.size)
                    ui.safeBottom =
                        geo.safeAreaInsets.bottom
                }
                .onChange(of: geo.size) { newSize in
                    syncWide(newSize)
                }
                .onChange(of: geo.safeAreaInsets.bottom) {
                    sb in
                    // CREATE kb 打点：首次由 0 变非零
                    // ≈ 键盘开始呈现（落定近似）。
                    if ui.safeBottom == 0 && sb > 0 {
                        editor.noteCreateKb()
                    }
                    ui.safeBottom = sb
                    // 键盘可见边沿（完成胶囊触发源）
                    // 不在此发布：safeBottom 静息 = 设
                    // 备安全区（非 0），sb > 0 派生会
                    // 在首次升起后闩锁为真、胶囊永不
                    // 回缩（0.9.56 真机回归，定案
                    // fix_donecapsule_retract.md）；
                    // kbVisible 已移交 EditorUI 的键
                    // 盘通知单点喂入，本段只管量测类
                    // 三件（safeBottom/CREATE/kbPad）。
                    // 底距落定应用（0.9.48）：动画期逐
                    // 帧值只记 safeBottom，kbPad 去抖后
                    // 一次生效、不逐帧重排内容。
                    ui.settleKbPad(sb)
                }
        })
        .onAppear {
            Library.markScene(LaunchStep.sceneEditor)
            // 打开留痕单点收敛（G4）：行点按/网格/右
            // 键菜单/wiki/反向链接全部入口都经本页出
            // 现，一处记行即全覆盖（Web row open 口径）。
            DiagLog.shared.log(.info,
                "APP row open \(editor.item.id)")
            DiagLog.shared.log(.info,
                "SCROLL open blocks=\(editor.blocks.count) "
                + "types=\(editor.blocks.map { $0.type }.joined(separator: ","))")
            // 标题草稿/反链初值已在 init 种子化
            // （0.9.48），此处不再回写 @Published 触
            // 发二次全量 body（治 S2）。
            // 菜单整树惰性预建：改挂转场落定事件
            // （editor.settleTick，宿主在转场落定单
            // 点发布）——已落定呈现（关联替换等）
            // settleTick 已 >0、本轮即建；普通 push
            // 由下方 onChange 在落定拍建。旧
            // onAppear + 0.6s 经验常数定时预建已删
            // （补丁债偿还批一 A-7），稳态打开的进
            // 出场动画口径不变。
            if editor.settleTick > 0, !ui.menuBuilt {
                ui.menuBuilt = true
            }
            // 新建篇初始落焦：由首个文本块视图认领
            // （BlockTextView.updateUIView），但须等
            // 转场宿主在 push 落定后开门（0.9.50 呈现
            // 重构：认领不再落在转场中段、键盘不与转
            // 场抢帧）。此处只记 CREATE 计时的出现点。
            editor.markCreateAppear()
        }
        .toolbar(.hidden, for: .navigationBar)
        // 图片页呈现已移交转场宿主（0.9.50）：旧形态
        // 经本视图的 navigationDestination 挂在首页
        // NavigationStack 上；编辑器改由 UIKit push
        // 承载后无栈祖先可挂，改由宿主订阅
        // editor.imageTarget 直接 push 图片页承载控
        // 制器（置位 push/清空 pop/关闭反向清空，语
        // 义逐项等价，见 MomentEditorTransition）。
        .onChange(of: editor.linkFormBlockId) { id in
            if id != nil {
                ui.linkDraft = "https://"
                ui.linkError = false
            }
        }
        .onDisappear {
            let estH = editor.blocks.reduce(0) {
                $0 + $1.height
            } + CGFloat(max(0, editor.blocks.count - 1)) * 6
                + 155 + 220 + 40
            DiagLog.shared.log(.info,
                "SCROLL close maxY=\(Int(editor.scrollState.maxScrollY)) "
                + "estContentH=\(Int(estH)) "
                + "viewH=\(Int(ui.viewH)) "
                + "heights=\(editor.blocks.map { Int($0.height) })")
            editor.saveNow()
        }
        .animation(.easeOut(duration: 0.18),
                   value: editor.slashBlockId ?? "")
        .confirmationDialog(Lang.t("editor.avatar_title"),
            isPresented: Binding(
                get: { ui.showAvatarChoice },
                set: { ui.showAvatarChoice = $0 }),
            titleVisibility: .visible) {
            Button(Lang.t("editor.avatar_change")) { ui.showAvatarPicker = true }
            Button(Lang.t("editor.avatar_reset"), role: .destructive) {
                editor.library.setAvatar(
                    for: editor.item.id, dataURL: nil)
            }
            Button(Lang.t("action.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { ui.showAvatarPicker },
            set: { ui.showAvatarPicker = $0 })) {
            PhotoPicker { data, _ in
                // 统一转 JPEG data URL 存 avatars 通道
                // （与 Web 文件直读形同为 data URL）。
                if let img = UIImage(data: data),
                   let jpg = img.jpegData(
                    compressionQuality: 0.85) {
                    editor.library.setAvatar(
                        for: editor.item.id,
                        dataURL: "data:image/jpeg;base64,"
                            + jpg.base64EncodedString())
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { ui.showPhotoPicker },
            set: { ui.showPhotoPicker = $0 })) {
            PhotoPicker(
                onPick: { data, pname in
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    guard editor.library.putAttachment(
                        fid, data, name: pname) else {
                        DiagLog.shared.log(.error,
                            "选图未成块（附件写入失败）fid=\(fid)")
                        return
                    }
                    editor.addImageBlock(fileId: fid)
                },
                allowVideo: true,
                onPickVideo: { data, pname in
                    // 选片路视频分流（F-15）：成 video
                    // 块而非图片/附件块。
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    guard editor.library.putAttachment(
                        fid, data, name: pname) else {
                        DiagLog.shared.log(.error,
                            "选视频未成块（附件写入失败）fid=\(fid)")
                        return
                    }
                    editor.addVideoBlock(fileId: fid)
                })
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { editor.showReplacePicker },
            set: { editor.showReplacePicker = $0 })) {
            PhotoPicker { data, pname in
                let fid = "att-" + UUID().uuidString
                    .prefix(12).lowercased()
                guard editor.library.putAttachment(
                    fid, data, name: pname) else {
                    DiagLog.shared.log(.error,
                        "换图未生效（附件写入失败）fid=\(fid)")
                    return
                }
                editor.replaceImage(fileId: fid)
            }
            .ignoresSafeArea()
        }
        // B-06（m-05）：系统 sheet 唤起前清斜杠会
        // 话——Web openSlashImage/openSlashGallery
        // 在 input.click 前 closeMenu；原生 sheet
        // 关闭后焦点回文本视图重跑 updateSlash，
        // 陈旧会话令面板在选图返回后复现（幽灵面
        // 板）。三 sheet 呈现真值任一转真即清面板
        // 态；token 文本不动（closeMenu 只关菜单
        // 同界），linkForm 会话独立、不在此列。
        .onChange(of: ui.showPhotoPicker) { v in
            if v { editor.slashBlockId = nil }
        }
        .onChange(of: ui.showFilePicker) { v in
            if v { editor.slashBlockId = nil }
        }
        .onChange(of: editor.showReplacePicker) { v in
            if v { editor.slashBlockId = nil }
        }
        .modifier(CardEditSheets(editor: editor, ui: ui))
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        .confirmationDialog(Lang.t("menu.attach"),
            isPresented: Binding(
                get: { ui.showAttachChoice },
                set: { ui.showAttachChoice = $0 }),
            titleVisibility: .visible) {
            Button(Lang.t("attach.pick_media")) { ui.showPhotoPicker = true }
            Button(Lang.t("attach.pick_file")) { ui.showFilePicker = true }
            Button(Lang.t("action.cancel"), role: .cancel) {}
        }
        .fileImporter(isPresented: Binding(
            get: { ui.showFilePicker },
            set: { ui.showFilePicker = $0 }),
            allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                if let data = try? Data(contentsOf: url) {
                    let fid = "att-" + UUID().uuidString
                        .prefix(12).lowercased()
                    guard editor.library.putAttachment(
                        fid, data,
                        name: url.lastPathComponent) else {
                        DiagLog.shared.log(.error,
                            "附件未成块（写入失败）fid=\(fid)")
                        return
                    }
                    // 视频分流（F-15）：系统内容类型
                    // （资源值优先、扩展名兜底）合
                    // .movie 者成 video 块，不再降为
                    // 附件文件行；余皆维持附件块。
                    let ftype = (try? url.resourceValues(
                        forKeys: [.contentTypeKey]))?
                        .contentType
                        ?? UTType(filenameExtension:
                            url.pathExtension)
                    if ftype?.conforms(to: .movie) == true {
                        editor.addVideoBlock(fileId: fid)
                    } else {
                        editor.addAttachmentBlock(
                            fileId: fid,
                            name: url.lastPathComponent,
                            size: data.count)
                    }
                }
            }
        }
    }

    // 斜杠面板（Web 口径）：空查询 = 最近使用 + 基础块 +
    // 媒体块分组；有查询 = 拼音/关键词/中文过滤平铺；
    // 无匹配出提示行。点选即执行（Editor 作用域）。
    /// 卡片浮层菜单呈现层（Web CardMenuLayer 口径）：
    /// 错误徽章层（Web .eb-badge/.eb-panel 口径）：
    /// 贴卡下 8px、放不下上翻、宽 216、高按项数（有
    /// 编辑 114 / 无 64）；点遮罩关闭（并退出可能残
    /// 留的卡编辑态，Web 口径）。独立成段避免 EditorView
    /// body 类型检查超时。
    private var cardMenuLayer: some View {
        GeometryReader { geo in
            let menuBid = editor.cardMenuBlockId ?? ""
            let blk = editor.blocks.first { $0.id == menuBid }
            let top = (blk?.frameMinY ?? 160)
                + (editor.twoPaneIndependent ? 155 : 0)
            let bh = blk?.height ?? 24
            let hasEdit = blk.map {
                EditorModel.editCardTypes.contains($0.type)
            } ?? false
            let panelH: CGFloat = hasEdit ? 114 : 64
            let below = top + bh + 8
            let panelTop = below + panelH
                > geo.size.height - 12
                ? max(12, top - 8 - panelH)
                : below
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    editor.cardMenuBlockId = nil
                    editor.exitCardEdit(via: "scrim")
                }
            cardMenuPanel(block: blk, hasEdit: hasEdit)
                .frame(width: 216)
                .position(x: panelLeftX(block: blk,
                                        panelW: 216,
                                        viewW: geo.size.width)
                            + 108,
                          y: panelTop + panelH / 2)
        }
    }

    /// 浮层面板左缘（屏幕坐标）：锚触发块所在栏左缘，
    /// 视口两侧 12 钳制。单列/flow 下块的 frameMinX 已
    /// 是全内容坐标；independent 右栏是栏内坐标，须加
    /// 栏原点（边距 + 栏宽 + 栏距）。
    private func panelLeftX(block: BlockState?,
                            panelW: CGFloat,
                            viewW: CGFloat) -> CGFloat {
        guard let block else { return 16 }
        var x = 16 + block.frameMinX
        if editor.twoPaneIndependent && ui.wide,
           let idx = editor.blocks.firstIndex(
            where: { $0.id == block.id }),
           idx >= min(editor.columnBoundaryIndex,
                      editor.blocks.count) {
            let contentW = min(viewW, 1440)
            let margin = (viewW - contentW) / 2 + 16
            let gap = min(52, max(28, viewW * 0.032))
            // 右栏原点账（L-2 栏内距后）：左栏宽 =
            // （内容宽 − 横边距 32 − 线 1）/ 2，其后
            // 线 1 + 右内距（gap + 15）即右内容左缘。
            let colW = (contentW - 32 - 1) / 2
            x = margin + colW + 1 + gap + 15
                + block.frameMinX
        }
        return min(max(x, 12), max(12, viewW - panelW - 12))
    }

    /// 卡片浮层菜单本体（Web .card-menu-panel：项与
    /// ••• 菜单同 menuItem 度量，浮层档、radius 22）。
    private func cardMenuPanel(block: BlockState?,
                               hasEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasEdit, let block {
                menuItem(icon: "pencil", title: Lang.t("cardmenu.edit")) {
                    editor.cardMenuBlockId = nil
                    if block.type == "musicCard" {
                        // 音乐卡编辑 = 即时输 URL 动作
                        // （Web 口径，无持续编辑态）。
                        ui.musicURLDraft =
                            block.node["url"] as? String ?? ""
                        ui.musicEditBlockId = block.id
                    } else {
                        editor.cardEditBlockId = block.id
                        DiagLog.shared.log(.info,
                            "EDIT card edit enter \(block.id) "
                            + "(\(block.type))")
                    }
                }
            }
            if let block {
                menuItem(icon: "trash", title: Lang.t("editor.delete_block"),
                         danger: true) {
                    editor.cardMenuBlockId = nil
                    if editor.cardEditBlockId == block.id {
                        editor.cardEditBlockId = nil
                    }
                    editor.deleteBlock(block)
                    DiagLog.shared.log(.info,
                        "EDIT card menu delete \(block.id)")
                }
            }
        }
        .padding(7)
        .overlayCard()
    }

    /// 块类型转换菜单呈现层（0.9.47）：锚定/翻转/钳
    /// 制与 cardMenuLayer 同口径；由按压引擎拾起时
    /// 置位 blockMenuBlockId（行侧 onPickup），转入
    /// 拖动自动收起、原地松手留存，点遮罩关闭。项
    /// 集 = 旧 .contextMenu 全集（文本块七项转换 +
    /// 删除块；非文本非卡行只有删除块），面板高按
    /// 项数（menuItem 50/项 + 内距 14）、上限 340
    /// 超出内滚。
    private var blockMenuLayer: some View {
        GeometryReader { geo in
            let menuBid = editor.blockMenuBlockId ?? ""
            let blk = editor.blocks.first { $0.id == menuBid }
            let top = (blk?.frameMinY ?? 160)
                + (editor.twoPaneIndependent ? 155 : 0)
            let bh = blk?.height ?? 24
            let itemCount = (blk?.isText == true ? 7 : 0) + 1
            let panelH = min(CGFloat(itemCount) * 50 + 14,
                             340)
            let below = top + bh + 8
            let panelTop = below + panelH
                > geo.size.height - 12
                ? max(12, top - 8 - panelH)
                : below
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    editor.blockMenuBlockId = nil
                }
            blockMenuPanel(block: blk)
                .frame(width: 216, height: panelH)
                .position(x: panelLeftX(block: blk,
                                        panelW: 216,
                                        viewW: geo.size.width)
                            + 108,
                          y: panelTop + panelH / 2)
        }
    }

    /// 类型转换菜单本体（项与动作 = 旧 .contextMenu
    /// 全集同义；浮层档、radius 22 与卡菜单同形态）。
    private func blockMenuPanel(block: BlockState?)
        -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let block, block.isText {
                    menuItem(icon: "text.alignleft",
                             title: Lang.t("menu.paragraph")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "paragraph")
                    }
                    menuItem(icon: "textformat.size",
                             title: Lang.t("slash.heading1")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 1)
                    }
                    menuItem(icon: "textformat.size",
                             title: Lang.t("slash.heading2")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 2)
                    }
                    menuItem(icon: "textformat.size",
                             title: Lang.t("slash.heading3")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 3)
                    }
                    menuItem(icon: "checklist",
                             title: Lang.t("slash.todo")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "todo")
                    }
                    menuItem(icon: "quote.opening",
                             title: Lang.t("slash.quote")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "quote")
                    }
                    menuItem(icon: "exclamationmark.bubble",
                             title: Lang.t("callout.tip")) {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "callout")
                    }
                }
                if let block {
                    menuItem(icon: "trash", title: Lang.t("menu.delete_block"),
                             danger: true) {
                        editor.blockMenuBlockId = nil
                        editor.deleteBlock(block)
                        DiagLog.shared.log(.info,
                            "DRAG menu delete id=\(block.id)")
                    }
                }
            }
            .padding(7)
        }
        .overlayCard()
    }

    /// 斜杠/链接面板浮层（从 body 拆出独立计算属性：
    /// EditorView.body 有类型检查超时前科，呈现段一律
    /// 拆出、body 只留一行引用）。锚定触发块（Web
    /// render.rs:651-659 口径）：锚底 + 10 定顶边、放
    /// 不下按实测高上翻、限高随锚位动态收缩（min
    /// (320, 视口 − 顶边 − 16)；上翻支下限 120 为横
    /// 屏矮高保底——Web 仅 320 硬顶、无锚位下限，
    /// 此为原生保底不冲突，审计 L-3）。此前按 320
    /// 写死估高定中心，短列表顶边下移可达约 100px
    /// （线 2 #52）。占位账：纵向锚优先触发行
    /// （B-03：slashAnchor*Y 窗口系，与横向锚同通
    /// 道同源）——belowTop = 行底 + 10、上翻与限
    /// 高按行顶算；锚缺失/异块回退旧账：top = 触
    /// 发块顶（frameMinY，independent +155 与卡
    /// 菜单同口径）、belowTop = top + 块高 + 10。
    /// 底安全距 12（Web 判翻 vh−8 的既有近似）。
    private var slashLayer: some View {
        GeometryReader { geo in
            let blk = editor.blocks.first {
                $0.id == (editor.linkFormBlockId
                    ?? editor.slashBlockId)
            }
            let top = (blk?.frameMinY ?? 160)
                + (editor.twoPaneIndependent ? 155 : 0)
            let bh = blk?.height ?? 24
            let panelW = slashPanelWidth(
                viewW: geo.size.width)
            let viewH = geo.size.height
            let hRaw = min(
                ui.slashPanelH > 0
                    ? ui.slashPanelH
                    : slashEstimateH(), 320)
            let anchored = blk != nil
                && editor.slashAnchorBlockId == blk?.id
            let anchorTop = anchored
                ? editor.slashAnchorTopY : top
            let belowTop = anchored
                ? editor.slashAnchorBottomY + 10
                : top + bh + 10
            let flipped = belowTop + hRaw > viewH - 12
            let panelTop = flipped
                ? max(12, anchorTop - 10 - hRaw) : belowTop
            let maxH = flipped
                ? min(320, max(anchorTop - 10 - 12, 120))
                : min(320, viewH - panelTop - 16)
            let h = max(min(hRaw, maxH), 0)
            Group {
                if editor.linkFormBlockId != nil {
                    linkFormPanel(maxH: maxH)
                } else {
                    slashPanel(maxH: maxH)
                }
            }
            .frame(width: panelW)
            .onGeometryChange(
                for: CGFloat.self
            ) { proxy in
                proxy.size.height
            } action: { newH in
                if abs(newH - ui.slashPanelH) > 0.5 {
                    ui.slashPanelH = newH
                }
                // cap 同点回写（U2）：maxH 与上方渲
                // 染同一局部值，零第二公式。
                if abs(maxH - ui.slashPanelMaxH) > 0.5 {
                    ui.slashPanelMaxH = maxH
                }
            }
            .position(
                x: slashPanelLeft(panelW: panelW,
                                  viewW: geo.size.width)
                    + panelW / 2,
                y: panelTop + h / 2)
        }
        .transition(.opacity)
    }

    /// 斜杠面板宽（J2-F17，Web render.rs:637-650 公
    /// 式逐项移植）：每行估宽 = 24（图标槽）+ 10（行
    /// 间距）+ 标题字数 ×16 +（有 shortcut 时 8 +
    /// 其字数 ×8）+ 22（行右内距），分组命令另 +20
    /// （最近丸预留）；内容宽初值 240、全命令取大；
    /// 面板宽 = min(360, max(220, 内容宽 + 12,
    /// 视口宽 − 24))。标题取当前呈现串（SlashCmds
    /// 数据表即呈现源，与 Web 的 i18n t() 同源口
    /// 径；i18n I4 换键后自动跟随）。
    private func slashPanelWidth(viewW: CGFloat) -> CGFloat {
        var maxContent: CGFloat = 240
        for c in SlashCmds.all {
            var w: CGFloat = 24 + 10
                + CGFloat(c.title.count) * 16 + 22
            if !c.shortcut.isEmpty {
                w += 8 + CGFloat(c.shortcut.count) * 8
            }
            if c.group > 0 { w += 20 }
            if w > maxContent { maxContent = w }
        }
        return min(360, max(220, maxContent + 12,
                            viewW - 24))
    }

    /// 斜杠面板左缘（J2-F18，Web render.rs:650）：
    /// left = min(视口宽 − 面板宽 − 12, 锚 X − 8)，
    /// 再钳 ≥12（窗口左缘即视口左缘 vx=0）。
    private func slashPanelLeft(panelW: CGFloat,
                                viewW: CGFloat) -> CGFloat {
        max(min(viewW - panelW - 12,
                editor.slashAnchorX - 8), 12)
    }

    /// 斜杠面板首帧构成估高（实测回写前避免跳变）：
    /// 16（内距）+ 组头数 × 30 + 行数 × 48，钳
    /// [48, 320]；空态约 120。与 slashPanel 同源
    /// （SlashCmds.rows 单源计数）。
    private func slashEstimateH() -> CGFloat {
        let rows = SlashCmds.rows(editor.slashQuery)
        var headers = 0
        var cmds = 0
        for r in rows {
            switch r {
            case .head: headers += 1
            case .cmd: cmds += 1
            }
        }
        let est: CGFloat = cmds == 0
            && !editor.slashQuery.isEmpty
            ? 120
            : 16 + CGFloat(headers) * 30
                + CGFloat(cmds) * 48
        return min(max(est, 48), 320)
    }

    private func slashPanel(maxH: CGFloat) -> some View {
        let q = editor.slashQuery
        let rows = SlashCmds.rows(q)
        let hasCmd = rows.contains {
            if case .cmd = $0 { return true }
            return false
        }
        return VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !hasCmd {
                            slashEmptyState
                        } else {
                            ForEach(Array(rows.enumerated()),
                                    id: \.offset) { idx, row in
                                switch row {
                                case .head(let title):
                                    slashGroupHeader(
                                        title,
                                        first: idx == 0)
                                case .cmd(let cmd,
                                          let recent,
                                          let cidx):
                                    slashRow(
                                        cmd, recent: recent,
                                        selected: cidx
                                            == editor.slashSel,
                                        query: q, cidx: cidx)
                                        .id("slash-row-\(cidx)")
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: editor.slashSel) { sel in
                    // 选中行跟随（Web setSel 的 scroll-
                    // IntoView nearest 口径；scrollTo
                    // 无锚点 = 最小滚动到可见）。
                    proxy.scrollTo("slash-row-\(sel)")
                }
            }
        }
        .frame(maxHeight: maxH)
        .overlayCard()
    }

    /// 斜杠空态（Web .slash-empty-state 口径，J2-F25）：
    /// 容器 padding 24/12/20、主文 13 次级色、图标
    /// 28 + opacity 0.45 + 下距 8、提示 11 次级色
    /// opacity 0.75 + 上距 8。
    private var slashEmptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: f28))
                .foregroundStyle(
                    T.textSecondary.opacity(0.45))
                .padding(.bottom, 8)
            Text(Lang.t("slash.no_match"))
                .font(.system(size: f13))
                .foregroundStyle(T.textSecondary)
            HStack(spacing: 4) {
                Text(Lang.t("slash.empty_hint_lead"))
                slashKbd("bt")
                Text(Lang.t("slash.empty_hint_1") + " ·")
                slashKbd("tp")
                Text(Lang.t("slash.empty_hint_2") + " ·")
                slashKbd("yykp")
                Text(Lang.t("slash.empty_hint_3"))
            }
            .font(.system(size: f11))
            .foregroundStyle(T.textSecondary)
            .opacity(0.75)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private func slashKbd(_ t: String) -> some View {
        Text(t)
            .font(.system(size: f10, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(T.fillHover,
                        in: RoundedRectangle(
                            cornerRadius: 4))
    }

    /// 斜杠组头（Web .slash-section-heading 口径，
    /// J2-F22）：padding 6/8/4、11/700、tracking
    /// 0.035em（=0.385pt）、uppercase、opacity 0.8；
    /// 非首组顶缘 0.5 边线（--border-color）贴组头
    /// 盒顶、不另加纵向 spacer。
    private func slashGroupHeader(_ t: String,
                                  first: Bool) -> some View {
        Text(t)
            .font(.system(size: f11, weight: .bold))
            .tracking(0.385)
            .textCase(.uppercase)
            .foregroundStyle(
                T.textSecondary.opacity(0.8))
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity,
                   alignment: .leading)
            .overlay(alignment: .top) {
                if !first {
                    Rectangle()
                        .fill(T.borderSoft)
                        .frame(height: 0.5)
                }
            }
    }

    /// 斜杠行命中高亮文本（Web .slash-match）：命
    /// 中段 fill-accent-18 底 + 字重 650（semibold
    /// 近似）+ 主色；padding 0 2px/radius 3 在
    /// AttributedString 无对应面（同 == 高亮先例，
    /// 登记近似：仅底色+字重+字色）。
    private func slashHlText(_ text: String,
                             query: String,
                             size: CGFloat,
                             weight: Font.Weight,
                             color: Color) -> Text {
        func seg(_ s: String) -> AttributedString {
            var a = AttributedString(s)
            a.font = .system(size: size, weight: weight)
            a.foregroundColor = color
            return a
        }
        let (pre, mid, post) = SlashCmds.hlParts(
            text, SlashCmds.normQuery(query))
        guard let mid else { return Text(seg(text)) }
        var m = AttributedString(mid)
        m.font = .system(size: size, weight: .semibold)
        m.foregroundColor = T.textMain
        m.backgroundColor = T.fillAccent18
        return Text(seg(pre) + m + seg(post))
    }

    private func slashRow(_ cmd: SlashCmd,
                          recent: Bool = false,
                          selected: Bool = false,
                          query: String = "",
                          cidx: Int = -1) -> some View {
        Button {
            editor.applySlash(cmd.act)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: cmd.icon)
                    // 字形封顶（impl_dt_layout_resilience）：
                    // 同 menuItem 口径，封顶至槽宽 24。
                    .font(.system(size: min(f20, 24)))
                    .foregroundStyle(T.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        slashHlText(cmd.title, query: query,
                                    size: f14,
                                    weight: .semibold,
                                    color: T.textMain)
                        if recent {
                            // 最近丸（Web .slash-recent-
                            // pill + 面板覆盖口径，J2-F24）：
                            // 字 11、glass-label 色、pad
                            // 2/6、胶囊 glass-control 底 +
                            // 0.5 glass-control 边。
                            Text(Lang.t("slash.recent_pill"))
                                .font(.system(size: f11))
                                .foregroundStyle(T.glassLabel)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    T.glassControlTint,
                                    in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(
                                        T.glassBorder,
                                        lineWidth: 0.5)
                                }
                        }
                    }
                    slashHlText(cmd.sub, query: query,
                                size: f12, weight: .regular,
                                color: T.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if !cmd.shortcut.isEmpty {
                    Text(cmd.shortcut)
                        .font(.system(size: f11,
                                      design: .monospaced))
                        .foregroundStyle(T.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            T.fillHover,
                            in: RoundedRectangle(
                                cornerRadius: 6))
                        // 面板内丸整体 opacity 0.78
                        // （Web .slash-panel .slash-
                        // shortcut !important，J2-F23）。
                        .opacity(0.78)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .background {
                // 键盘选中态（Web .slash-row.sel =
                // fill-hover）。
                if selected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(T.fillHover)
                }
            }
        }
        .buttonStyle(RowPressStyle(radius: 14))
        .onHover { hovering in
            // 指针悬停设选（Web mouseenter → setSel）。
            if hovering && cidx >= 0 {
                editor.slashSel = cidx
            }
        }
        // 行间外距（Web .slash-row margin:1px 0，
        // J2-F21）：相邻行间合成 2、首尾各 1。
        .padding(.vertical, 1)
    }

    /// 链接表单（Web .slash-link-form 口径）：面板内原
    /// 地替换列表——标题、预填 https:// 的输入框、校验
    /// 失败才出现的错误行、右对齐双胶囊钮。
    // maxH = 斜杠层可用高（impl_dt_layout_resilience）：
    // 表单自然高在大字号下约 300，矮高 × 大字号 ×
    // 低位块组合下旧形态靠测量定位、无高帽会两端
    // 溢出锚框——改限高内滚，卡面（overlayCard）
    // 挂滚动容器外层固定；默认档内容恒低于 maxH、
    // 呈现逐值不变。
    private func linkFormPanel(maxH: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 10) {
            Text(Lang.t("slash.link_form_title"))
                .font(.system(size: f14, weight: .semibold))
                .foregroundStyle(T.textMain)
            TextField("https://example.com",
                      text: Binding(
                        get: { ui.linkDraft },
                        set: { ui.linkDraft = $0
                               ui.linkError = false }))
                .font(.system(size: f14))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                // 输入框（Web .slash-link-input 口径，
                // J2-F26）：padding 9/11、1px
                // --border-color 边、radius 10、
                // fill-subtle 底、min-height 44。
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .background(T.fillSubtle,
                            in: RoundedRectangle(
                                cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(T.borderSoft,
                                      lineWidth: 1)
                }
                .focused($linkFieldFocused)
                .onSubmit { submitLinkForm() }
            if ui.linkError {
                Text(Lang.t("slash.link_invalid"))
                    .font(.system(size: f12))
                    .foregroundStyle(T.danger)
            }
            HStack(spacing: 8) {
                Spacer()
                // 双钮同规（Web .slash-link-actions 口
                // 径，J2-F27）：字 600 13、min-width 76、
                // min-height 44、padding 0/14、1px 边、
                // radius 999；取消钮边 --border-color，
                // 提交钮边透明（同盒）。
                Button(Lang.t("action.cancel")) {
                    // 回命令列表（Web 口径，与 Esc 同）。
                    editor.linkFormBlockId = nil
                }
                .font(.system(size: f13, weight: .semibold))
                .foregroundStyle(T.textMain)
                .padding(.horizontal, 14)
                .frame(minWidth: 76, minHeight: 44)
                .background(T.fillHover,
                            in: Capsule())
                .overlay {
                    Capsule().strokeBorder(T.borderSoft,
                                           lineWidth: 1)
                }
                Button(Lang.t("slash.link_insert")) { submitLinkForm() }
                    .font(.system(size: f13, weight: .semibold))
                    .foregroundStyle(T.onAccent)
                    .padding(.horizontal, 14)
                    .frame(minWidth: 76, minHeight: 44)
                    .background(T.accent, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.clear,
                                               lineWidth: 1)
                    }
            }
        }
        .padding(12)
        }
        .frame(maxHeight: maxH)
        .overlayCard()
        .onAppear { linkFieldFocused = true }
    }

    private func submitLinkForm() {
        if editor.applyLink(url: ui.linkDraft) {
            ui.linkDraft = ""
            ui.linkError = false
        } else {
            ui.linkError = true
        }
    }

    // 页眉结构（根治）：单行 HStack = 返回钮 / 坞 / 更多
    // 钮，两侧等宽 Spacer 使坞居中、三者同顶线。旧
    // ZStack 叠层形态在真机上两钮不呈现（用户截图实
    // 证），弃用叠层、改流式同行布局，构造上不可能丢钮。
/// 编辑页页眉（独立视图结构体）：滚动偏移的观察隔离
/// 在此——scrollY 每帧变化只重演算页眉子树，不再连带
/// 整个块列表（长笔记滚动卡死/掉帧的根治；审计外
/// 用户实报「有些笔记滚动不了」）。
struct EditorHeaderView: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject var ui: EditorView.EditorUI
    @ObservedObject var scroll: EditorScrollState
    /// 返回出口（0.9.50）：EditorView.onClose 下传，
    /// 由转场宿主 pop；在位时优先于环境 dismiss
    /// （呈现已改 UIKit push，dismiss 口径不作数）。
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// 标题焦点状态位（B-4 路径 B）：单一真相在
    /// TitleFieldControl（普通 Bool 状态）；字段
    /// 执行器（TitleTextField）据此 become/
    /// resign，真实第一响应者经委托回调收敛回
    /// 写。@FocusState 管不了 representable 字
    /// 段故退场；段内读点经 titleFocused 别名保
    /// 持不变（坞锁存/宽度/截断派生同源）。
    @StateObject private var titleControl =
        TitleFieldControl()
    private var titleFocused: Bool {
        titleControl.focused
    }

    /// 页眉量测通道（0.9.48，治 S2）：页眉可用宽只
    /// 被本视图的标题胶囊（capsuleWidth）消费，独立
    /// 观察对象自消费——旧实现经 EditorUI.headerW
    /// （@Published）回写，首帧量得即整页 body 多一
    /// 轮（T4）。与 scrollState 的隔离口径同理：量
    /// 测发布只失效消费它的子树。
    final class HeaderMeasure: ObservableObject {
        @Published var headerW: CGFloat = 0
    }
    @StateObject private var measure = HeaderMeasure()

    // 文字大小跟随系统（Dynamic Type 全量实装，
    // impl_dynamic_type_full）：页眉内无语义样式
    // 等值的字号走 ScaledMetric——f14 与标题字
    // 段字体（Marks.dynFont(size: 14, weight:
    // .semibold)，.body 样式）同缩放比、f10 与
    // meta 量测字体（dynFont(size: 10, style:
    // .caption2)）同缩放比，渲染与量测恒同源。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2)
    private var f10: CGFloat = 10
    @ScaledMetric(relativeTo: .title2)
    private var f22: CGFloat = 22
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15
    @ScaledMetric(relativeTo: .title3)
    private var f20: CGFloat = 20
    // 字体代次观察（fix_dynamic_type_follow）：类
    // 别变更时页眉重演算——TitleTextField 的
    // updateUIView 随之刷新字体三面、胶囊宽量测
    // 以新档 dynFont 重算。
    @ObservedObject private var fontHub = FontHub.shared

    /// 坞态实时派生：滚动过阈值为紧凑。段内阈值
    /// 字面仅此一处（T24-3 锁）。
    private var liveDockCompact: Bool {
        scroll.scrollY > 30
    }

    /// 会话锁存（横排点按卡死根治，定案 fix_title_
    /// compact_freeze.md）：标题会话开始那一刻的坞
    /// 态，整场保持不变。非会话期由 onAppear、滚
    /// 动变化、失焦三点同步为实时值；会话期内无
    /// 任何写者。这是 Web S7 的结构等价——Web 驱
    /// 动坞布局的是 ed_scroll 信号，编辑期滚动处
    /// 理只记抑制行、根本不写该信号，布局值冻结
    /// 在会话起点，失焦后由后续滚动按当刻值归
    /// 位。旧实现是活公式（紧凑 = 滚动过阈值 且
    /// 非编辑中）：紧凑态点按置焦的同一更新内公
    /// 式由真翻假，headerOverlay 在横/竖两分支间
    /// 换结构，焦点事务中的 TextField 随之销毁
    /// 重建——.focused 的目标视图其结构身份是焦
    /// 点值本身的函数（自指涉），焦点回滚与
    /// onChange 写 titleBase 的整树重演算叠加成
    /// 环，横排点按必卡死；竖排公式恒假不翻转，
    /// 故独正常。本工具链无 @State 宏插件，锁存
    /// 与翻转计数由 ObservableObject 承载（与
    /// HeaderMeasure 同纪律）。
    final class DockSession: ObservableObject {
        @Published var latchedCompact = false
        /// 坞分支翻转计数（面包屑）：分支每次真
        /// 翻转 +1 并随翻转行入 Diag；若再现风
        /// 暴，任意一行上的计数即量级证据（与
        /// Web dockflip 逐翻转记行同口径）。
        @Published var flipCount = 0
    }
    @StateObject private var dockSession = DockSession()

    /// 坞分支（单点）：会话中读锁存、非会话读实
    /// 时。headerOverlay、capsuleWidth 与动画值
    /// 共用此派生，防口径漂移。
    private var dockCompact: Bool {
        titleFocused ? dockSession.latchedCompact : liveDockCompact
    }

    var body: some View {
        ZStack {
            headerOverlay
            // Esc 收口的键盘入口（隐形钮，仅硬件键盘）。
            Button("") { handleEscape() }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        // 自检驱动注册（U1）：editor.view 面锚点
        // 挂页眉（编辑器在位期间页眉恒在层级，
        // 注册点即整篇编辑器的在位事实）——
        // frame 读 EditorUI 的 viewW/viewH 量
        // 测，close 走 closeEditor 具名入口，状
        // 态读直取编辑器模型与在席分叉判定。
        .background(UITestAnchor(providesFrame: true) {
            UITestSurfaceEntry(
                id: "editor.view", kind: "editor",
                instance: "-",
                frameInWindow: {
                    ui.viewW > 0
                        ? CGRect(x: 0, y: 0,
                                 width: ui.viewW,
                                 height: ui.viewH)
                        : nil
                },
                actions: [
                    "close": { _ in closeEditor() },
                ],
                state: [
                    "memoId": { editor.item.id },
                    "title": { editor.title },
                    "dirty": {
                        BridgeEditorSeat.isDiverged(
                            editor: editor,
                            library: editor.library)
                            ? "true" : "false"
                    },
                    "focusBlockId": {
                        editor.focusBlockId ?? ""
                    },
                    "draggingId": {
                        editor.draggingId ?? ""
                    },
                    // U4a 注册面扩展：坞态与滚动量
                    // （EDT-06 紧凑变体断言源——坞态
                    // 是页眉派生、滚动量在独立滚动
                    // 状态对象，均只此处可读）。
                    "dockCompact": {
                        dockCompact ? "true" : "false"
                    },
                    "scrollY": { "\(scroll.scrollY)" },
                ])
        })
        // 紧凑态切换（Web 口径）：0.25s 缓动。动画值在
        // 本视图内读 scrollY，滚动重演算不外溢。
        .animation(.easeInOut(duration: 0.25),
                   value: dockCompact)
        // —— 会话锁存的同步点与翻转面包屑（写者纪
        // 律见 DockSession 注释：同步写仅此三处，
        // F28-3 锁写者封闭）——
        .onAppear { dockSession.latchedCompact = liveDockCompact }
        .onChange(of: scroll.scrollY) { _ in
            // 非会话期锁存跟随实时；会话期不写（冻
            // 结即 S7 抑制的落点）。值未变不写，免
            // 滚动帧频下无谓失效。
            if !titleFocused
                && dockSession.latchedCompact != liveDockCompact {
                dockSession.latchedCompact = liveDockCompact
            }
        }
        .onChange(of: titleControl.focused) { f in
            // 失焦归位：锁存同步回当刻实时值，分支
            // 随当刻滚动位置重定（Web 失焦后由后续
            // 滚动归位的即时等价）。
            if !f { dockSession.latchedCompact = liveDockCompact }
        }
        .onChange(of: dockCompact) { c in
            dockSession.flipCount += 1
            DiagLog.shared.log(.info,
                "EDIT dockflip compact=\(c ? 1 : 0) "
                + "src=\(titleFocused ? "session" : "scroll") "
                + "n=\(dockSession.flipCount)")
        }
    }

private var headerOverlay: some View {
    HStack(alignment: .top, spacing: 0) {
        Button {
            closeEditor()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: f22, weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .glassControl(radius: Radius.pill)
        }
        // 与坞紧贴（Spacer 0）：Web 坞 left/right 62
        // 恰与钮外缘紧贴（62 对 62）；留 8 间隔会使
        // 胶囊宽上限比横排实际可用多 16，长标题顶限
        // 时溢出、胶囊被挤出横排（用户实报定因）。
        Spacer(minLength: 0)
        if dockCompact {
            // 紧凑态（Web .editor-title-dock.scrolled
            // 真值）：同一坞转横排——头像 72 不变、胶囊
            // 66 不变、gap 8、仅 meta 行 display:none。
            // 旧自创小胶囊（头像 32 + 高 46）与 Web 两
            // 模两样，整套弃用、两态共用同一坞组件。
            HStack(spacing: 8) {
                avatarButton
                titleCapsule(compact: true)
            }
        } else {
            VStack(spacing: 6) {
                avatarButton
                titleCapsule(compact: false)
            }
        }
        Spacer(minLength: 0)
        moreCapsule
    }
    .padding(.horizontal, 16)
    .padding(.top, 7)
    .background {
        GeometryReader { geo in
            Color.clear
                .onAppear { measure.headerW = geo.size.width }
                .onChange(of: geo.size.width) { w in
                    measure.headerW = w
                }
        }
    }
}

/// 完成胶囊展开派生（单点）：键盘可见且无更高层
/// 浮层/手势占用时展开。抑制格（状态矩阵，定案
/// impl_editor_done_capsule.md）：菜单/导出面板
/// 在位（showMenu/showExport）、背景底表在位
/// （showBgSheet）、拖拽拾起中（draggingId）、
/// 卡片/块菜单在位（cardMenuBlockId/blockMenu-
/// BlockId）——这些浮层都在页眉之上或接管手势，
/// 完成段一律抑制、胶囊保持圆钮（点 ••• 开菜单
/// 时胶囊同拍缩回、面板自上方盖入，无稳态重
/// 叠）。斜杠面板与链接表单不抑制：同属编辑会
/// 话，完成即既有失焦链的确定性出口（与旧键盘
/// 上方工具栏钮在位时的可达口径一致）。
private var doneExpanded: Bool {
    ui.kbVisible
        && !ui.showMenu && !ui.showExport
        && !ui.showBgSheet
        && editor.draggingId == nil
        && editor.cardMenuBlockId == nil
        && editor.blockMenuBlockId == nil
}

/// 尾随竖向胶囊（用户 2026-11-27 规格）：••• 圆
/// 钮与键盘态「完成」同容器变形——键盘弹起时圆
/// 钮向下延展成竖向胶囊（上段 •••、下段打勾），
/// 点勾收键盘、胶囊随键盘落下缩回圆钮。单容器
/// 单玻璃面：宽恒 46（玻璃钮直径）、帧高 46↔92
/// 动画、顶锚定（容器帧 .top 对齐 + 页眉 HStack
/// .top 对齐，••• 段一像素不动、只向下生长），
/// 展开高 = 两段各 46 同径相接（段间 0、无分隔
/// 线）；玻璃半径 999 在宽 46 下钳为 23，圆↔胶
/// 囊随高连续变形，GlassCard 的 clipShape 同步
/// 裁切下段。勾淡入滞后于高度动画（展开延迟
/// 0.1s 起淡、0.15s 完），收起反序（勾无延迟先
/// 淡出、高度随后缩）。浮层不占位：页眉本身是
/// EditorView ZStack 的悬浮层，胶囊增高不推正
/// 文；右边距 = 页眉横距 16（与圆钮现行一致），
/// z 序在正文之上、菜单面板之下（ZStack 序）。
private var moreCapsule: some View {
    let expanded = doneExpanded
    return VStack(spacing: 0) {
        Button {
            toggleEditorMenu()
        } label: {
            Image(systemName: "ellipsis")
                // 字形封顶（impl_dt_layout_resilience）：
                // 椭圆字形宽 ≈ 1.0em，f22 在大字号档达
                // ≈69pt、超 46 槽且玻璃 clipShape 裁切
                // 两侧圆点——封顶 34（字形 ≈34 宽、槽
                // 内余量 6/侧），帧公式 46↔92 不动、
                // 默认档逐值不变（22 < 34 不触发）。
                .font(.system(size: min(f22, 34),
                              weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        Button {
            finishEditing()
        } label: {
            CheckmarkGlyph()
                .stroke(T.textMain, style: StrokeStyle(
                    lineWidth: 2.8, lineCap: .round,
                    lineJoin: .round))
                .frame(width: 22, height: 22)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .opacity(expanded ? 1 : 0)
        .allowsHitTesting(expanded)
        .accessibilityHidden(!expanded)
        .accessibilityLabel(Lang.t("editor.done_aria"))
        .animation(.easeInOut(duration: 0.15)
            .delay(expanded ? 0.1 : 0),
                   value: expanded)
    }
    .frame(width: 46, height: expanded ? 92 : 46,
           alignment: .top)
    // 自检驱动注册（U4a）：完成胶囊面——done 走
    // finishEditing 具名入口（与勾钮同一体），
    // expanded 读 doneExpanded 派生单源、kbVisible
    // 读键盘通知单点写位（EDT-09 断言源）。
    .background(UITestAnchor(providesFrame: false) {
        UITestSurfaceEntry(
            id: "editor.doneCapsule",
            kind: "capsule", instance: "-",
            actions: [
                "done": { _ in finishEditing() },
            ],
            state: [
                "expanded": {
                    doneExpanded ? "true" : "false"
                },
                "kbVisible": {
                    ui.kbVisible ? "true" : "false"
                },
            ])
    })
    .glassControl(radius: Radius.pill)
    .animation(.easeInOut(duration: 0.25),
               value: expanded)
    .onChange(of: expanded) { ex in
        DiagLog.shared.log(.info,
            "EDIT donecapsule \(ex ? "expand" : "collapse")")
    }
}

/// 「完成」（具名入口）：与旧键盘上方工具栏钮逐
/// 字同路——向响应链发送 resignFirstResponder，
/// 当前第一响应者走各自既有失焦链（标题字段 →
/// onEndEditing → commitTitle；块文本视图 →
/// textViewDidEndEditing 的提交/保存；链接表单
/// 字段同理），本入口不另做提交与保存。
private func finishEditing() {
    DiagLog.shared.log(.info, "EDIT donecapsule done")
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil)
}

/// 标题提交（Web 口径）：仅失焦/回车提交，编辑中不落
/// 盘；非编辑态超 10 字截断显示。
/// Esc 收口（E5，Web 口径）：硬件键盘 Esc 按浮层
/// 优先级关闭——链接表单 > 斜杠面板 > 背景色底表 >
/// 菜单/导出面板 > 标题编辑（还原草稿并失焦，标题
/// Esc 还原为 Web 标题控制器口径）。
private func handleEscape() {
    if editor.linkFormBlockId != nil {
        editor.linkFormBlockId = nil
        return
    }
    if editor.slashBlockId != nil {
        editor.slashBlockId = nil
        return
    }
    if ui.showBgSheet {
        ui.beginBgClose(apply: false, color: nil)
        return
    }
    if ui.showMenu || ui.showExport {
        ui.showMenu = false
        ui.showExport = false
        return
    }
    if titleFocused {
        // 组字守卫（m-01，Web title_controller 口
        // 径：composing 时 Esc 全忽略、不还原不
        // blur）——硬件键盘组字中 Esc 归输入法，
        // 不得直接还原草稿并辞焦。
        if titleControl.composing { return }
        ui.titleDraft = ui.titleBase
        titleControl.focused = false
    }
}

private func commitTitle() {
    // Web 口径：提交时 trim、空回退「无标题」（落盘
    // 值即回退值，与 Web 数据口径一致；审计 B-1）。
    // 落盘口径：会话结束即提交点——标题真变更时
    // 同步冲刷（saveNow），不走 scheduleSave 的
    // 0.6s 防抖：防抖是为正文键入流设的，标题提交
    // 是离散提交事件，若提交后库镜像（列表/桥回
    // 读）仍滞后一个防抖窗，提交点语义即不成立
    // （S1 步 3 两遍确定性回读旧标题定案，
    // fix_title_commit_propagation.md）。载荷与防
    // 抖路同一 preparedItem，只提前到提交点。
    let trimmed = ui.titleDraft.trimmingCharacters(
        in: .whitespacesAndNewlines)
    let final = trimmed.isEmpty ? Lang.t("editor.untitled") : trimmed
    if final != editor.title {
        editor.pushHistory()
        editor.title = final
        editor.saveNow()
        ui.backlinks = editor.library.backlinks(
            forTitle: editor.title,
            excludeId: editor.item.id)
    }
    if ui.titleDraft != final {
        ui.titleDraft = final
    }
}

/// ••• 菜单开关（U1 具名入口抽取）：页眉钮与
/// 驱动注册的 menuPanel 面 open/close 共用
/// ui.showMenu 一个状态位、同一呈现链，无第
/// 二入口（open/close 是其显式两向版）。
private func toggleEditorMenu() {
    ui.showMenu.toggle()
}

/// 编辑器关闭（U1 具名入口抽取）：返回钮动作
/// 体——commitTitle + saveNow + 返回出口（在
/// 位走宿主 pop、否则环境 dismiss）；驱动
/// editor.view 的 close 动作同路。
private func closeEditor() {
    commitTitle()
    editor.saveNow()
    if let onBack { onBack() } else { dismiss() }
}

/// 胶囊点按置焦（U1 具名入口 + B-4 落点映
/// 射，签名冻结 activateTitleFromCapsule
/// (atX:)）：截断覆盖层手势与驱动注册动作共
/// 用同一入口（单一来源）。落点映射在置焦之
/// 前以呈现态几何定格（方案 P5）：聚焦后胶
/// 囊宽动画展开、呈现态几何随即失效，故记号
/// 先算完存入 pendingCaret，落定后由字段
/// Coordinator 只施加不重算。无 atX（驱动程
/// 序化置焦）或非截断态不记号、不干预原生落
/// 点（与 Web 无记号口径一致）。
private func activateTitleFromCapsule(
    atX: CGFloat?) {
    DiagLog.shared.log(.info,
        "EDIT title focus via=capsule")
    if let atX, !titleFocused,
       ui.titleDraft.unicodeScalars.count > 10 {
        let full = ui.titleDraft
        let disp = scalarPrefix(full, 10) + "…"
        let caret = TitleTapCaret
            .caretScalarIndex(
                fullScalarCount:
                    full.unicodeScalars.count,
                prefixWidths:
                    titlePrefixWidths(disp),
                tapX: Double(atX),
                rowW: Double(capsuleWidth - 40))
        titleControl.pendingCaret = (
            scalar: caret,
            utf16: TitleTapCaret.utf16Offset(
                ofScalarIndex: caret,
                in: Array(full.unicodeScalars)))
    }
    titleControl.focused = true
}

/// 显示串逐前缀宽量测：属性集与 capsuleWidth
/// 现行量测同源（14 semibold + kern −0.2，
/// 方案 P2）。耦合钉子已随 Dynamic Type 全量
/// 实装拔除：标题字体三方（字段本体/胶囊量
/// 测/本量测）同走 TitleTextField.fieldFont()
/// 的 dynFont 缩放字体，字号随系统变、量测
/// 与呈现恒一致（impl_dynamic_type_full）。
private func titlePrefixWidths(
    _ disp: String) -> [Double] {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: TitleTextField.fieldFont(),
        .kern: -0.2,
    ]
    var out: [Double] = []
    var prefix = ""
    for s in disp.unicodeScalars {
        prefix.unicodeScalars.append(s)
        out.append(Double(prefix.size(
            withAttributes: attrs).width))
    }
    return out
}

/// 标题坞头像钮（两态共用，Web .editor-avatar-button
/// 口径）：72 圆、本篇头像、点按换图——有自定义头像
/// 时先出选择、无则直接选图。
private var avatarButton: some View {
    Button {
        if editor.library.avatarDataURL(
            for: editor.item.id) != nil {
            ui.showAvatarChoice = true
        } else {
            ui.showAvatarPicker = true
        }
    } label: {
        AvatarView(size: 72,
                   memoId: editor.item.id,
                   library: editor.library)
    }
    .buttonStyle(.plain)
}

private func titleCapsule(compact: Bool) -> some View {
    // 截断呈现态（未聚焦且标题超 10 标量）：旧实现
    // 以普通 Text 替换 TextField、点按时再程序化置
    // 焦——字段与置焦请求同事务入层级，且聚焦瞬间
    // onChange 写 titleBase（@Published）触发整树重
    // 演算，焦点请求被吞、FocusState 回滚到 false，
    // 呈现为「点击没反应、不能二次编辑」（用户
    // 0.9.53 实报；标题 ≤10 时字段常驻、点按走原生
    // 落焦，故首编独独可用）。根治：字段恒常驻层
    // 级（单一身份），截断形态改由覆盖层呈现（字
    // 段 opacity 0 仍在层级），点按覆盖层置焦时字
    // 段早已在层级——与音乐胶囊 focusMusicId 置焦
    // 同构的确定性路径，不再有插入/置焦竞态。
    let truncated = !titleFocused
        && ui.titleDraft.unicodeScalars.count > 10
    return VStack(spacing: 3) {
        ZStack {
            // 字段恒常驻（[24] 不变量的 B-4 结构
            // 版）：UITextField representable 只
            // 建一次、身份由 UIView 实例承载，
            // 常驻比 SwiftUI 字段更硬；截断态仍
            // 以 opacity 0 在层级、覆盖层呈现。
            // 会话开始/结束语义经字段委托回到下
            // 两闭包单点处理（快照/提交/Diag 与
            // 旧 onChange 两支路逐项等价；Enter
            // 收口在 Coordinator 的 shouldReturn
            // 辞焦后由结束支路提交，等价合流）。
            TitleTextField(
                control: titleControl,
                text: Binding(
                    get: { ui.titleDraft },
                    set: { ui.titleDraft = $0 }),
                onBeginEditing: {
                    // 聚焦快照：Esc 还原以会话起
                    // 点为准（审计 B-3）。
                    ui.titleBase = editor.title
                    DiagLog.shared.log(.info,
                        "EDIT title session begin "
                        + "len=\(ui.titleDraft.unicodeScalars.count)")
                },
                onEndEditing: {
                    DiagLog.shared.log(.info,
                        "EDIT title session end")
                    commitTitle()
                },
                onUndoKey: { isRedo in
                    // E2/F-12：标题字段 Cmd+Z 与正文
                    // 同走模型撤销漏斗。
                    if isRedo { editor.redo() }
                    else { editor.undo() }
                })
                .opacity(truncated ? 0 : 1)
                .accessibilityHidden(truncated)
                // 字段帧宽定值钉死（fix_title_
                // center_short_text 四修）：帧
                // 宽 = 胶囊定宽值 − 左右内距，
                // 与落点映射的 rowW 同源同式
                // （T24-12 跨点锁）。沿革：二修
                // （fix_title_capsule_center2）
                // 以弹性帧 (maxWidth: .infinity)
                // 占满行宽——其提议经父级提议
                // 透传，representable 的决定性
                // 量测仍落内容宽一档（与初版按
                // sizeThatFits 契约意图断言同
                // 型），0.9.65 真机复报真实短
                // 标题仍不居中、弹性帧证伪。
                // 定宽帧不经协商：帧布局恒以
                // 定值向子视图提议，sizeThat-
                // Fits 必走 definite 分支回告
                // 行宽、平台帧随之 = 行宽（帧
                // 随回告值的桥行为由 0.9.63 内
                // 容宽帧实况反证）；textAlign-
                // ment .center 与占位段落样式
                // （三修）就此在全行宽帧内生
                // 效。ZStack 宽 = 行宽、覆盖层
                // 几何与手势坐标系（行左缘原
                // 点）零改动，落点映射守恒。
                // 实效由设备探针 title_
                // geometry 量测（T24-12 锁链）。
                .frame(width: capsuleWidth - 40)
            if truncated {
                // 预览态居中（fix_title_capsule_
                // center）：覆盖层须自带字形居中
                // 指令。Text 帧经 maxWidth 占满行
                // 宽后，居中只能由 multiline 指令
                // 给到字形排布——此前缺此指令、
                // 字形按缺省 .leading 贴左内距。
                // 当时定性为「偏心唯一层位」；后
                // 0.9.63 真机复报短标题（字段形
                // 态）仍偏心，二次定性（fix_
                // title_capsule_center2）：预览
                // 态两呈现者各须自带显式居中构
                // 造——覆盖层 = 本指令 + 满宽帧，
                // 字段 = textAlignment .center
                // + 显式满宽帧（见字段侧注记）。
                // frame 与其后手势修饰序不动：
                // 手势坐标系（行左缘原点）不变，
                // 落点映射守恒。
                Text(scalarPrefix(ui.titleDraft, 10) + "…")
                    .font(.system(size: f14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture()
                        .onEnded { v in
                            activateTitleFromCapsule(
                                atX: v.location.x)
                        })
            }
        }
        // meta 行：紧凑态整行不渲染（Web .scrolled 下
        // display:none 的等价），不留占位、不外漏。
        if !compact {
            Text(metaLine)
                .font(.system(size: f10))
                .foregroundStyle(T.textSecondary)
                .lineLimit(1)
        }
    }
    .padding(.horizontal, 20)
    .frame(width: capsuleWidth, height: capsuleHeight)
    .glassControl(radius: Radius.titleCapsule)
    .animation(.easeInOut(duration: 0.2),
               value: capsuleWidth)
    // 自检驱动注册（U1）：胶囊面锚点——frame
    // 由锚点宿主视图几何填充（providesFrame
    // false，锚点即胶囊本体背景、几何同源）；
    // tap 走 activateTitleFromCapsule 具名入
    // 口（与手指同一闭包，驱动传 atX 为 nil 或
    // 指定值）、resign 为 Enter 收口同路、
    // escape 为 handleEscape 标题支同体。
    .background(UITestAnchor(providesFrame: false) {
        UITestSurfaceEntry(
            id: "editor.titleCapsule",
            kind: "capsule", instance: "-",
            actions: [
                "tap": { x in
                    activateTitleFromCapsule(
                        atX: x.map { CGFloat($0) })
                },
                "resign": { _ in
                    commitTitle()
                    titleControl.focused = false
                },
                "escape": { _ in
                    if titleControl.focused {
                        ui.titleDraft = ui.titleBase
                        titleControl.focused = false
                    }
                },
            ],
            state: [
                "focused": {
                    titleControl.focused
                        ? "true" : "false"
                },
                "truncated": {
                    (!titleControl.focused
                        && ui.titleDraft
                            .unicodeScalars.count
                            > 10)
                        ? "true" : "false"
                },
                "draftLen": {
                    "\(ui.titleDraft.unicodeScalars.count)"
                },
                "caretUTF16": {
                    "\(titleControl.caretUTF16)"
                },
                // 设备几何读数（探针 title_
                // geometry 的读源，fix_title_
                // center_short_text）：字段帧/
                // 字形块两缘的窗口坐标单串，
                // 读法与口径在 TitleField-
                // Control.titleGeometryString。
                "titleGeometry": {
                    titleControl
                        .titleGeometryString()
                },
            ],
            setText: { ui.titleDraft = $0 })
    })
}

/// 胶囊高（布局账，Dynamic Type 全量实装）：
/// 前提——默认档帧高 66 = 标题行行高（14
/// semibold 字体）+ 间距 3 + meta 行行高
/// （10 字体）+ 纵向留白（约 34），内容在帧
/// 内纵向居中。字号随系统放大后两行行高增
/// 长，定高 66 会先裁 meta 行；故帧高 = 66
/// + 两行行高相对默认档的增量（紧凑态 meta
/// 不渲染、只计标题行增量），默认档恒 66、
/// 与旧定高逐值一致。
private var capsuleHeight: CGFloat {
    let t = TitleTextField.fieldFont().lineHeight
    let t0 = UIFont.systemFont(
        ofSize: 14, weight: .semibold).lineHeight
    var delta = t - t0
    if !dockCompact {
        let m = Marks.dynFont(
            size: 10, style: .caption2).lineHeight
        let m0 = UIFont.systemFont(ofSize: 10)
            .lineHeight
        delta += m - m0
    }
    return 66 + max(0, delta)
}

private var capsuleWidth: CGFloat {
    let font = TitleTextField.fieldFont()
    // 量测串口径 = Web display_title_of（title.
    // rs）：空 →「无标题」；非编辑态超 10 标量 →
    // 前 10 标量 +「…」；编辑态恒全文（AUD-B-02，
    // 用户 2026-11-28 裁定对齐 Web 现行码；旧
    // 「恒显全文」口径作废）。
    let shown = ui.titleDraft.isEmpty
        ? Lang.t("editor.untitled")
        : (ui.titleDraft.unicodeScalars.count > 10 && !titleFocused
            ? scalarPrefix(ui.titleDraft, 10) + "…"
            : ui.titleDraft)
    // 量测须与呈现同字距（Web .editor-title-input
    // letter-spacing:-0.2px，J2-F01）：缺 kern 会按
    // 无字距宽定胶囊、长标题溢出/误截。
    let titleW = shown.size(
        withAttributes: [.font: font,
                          .kern: -0.2]).width
    // 胶囊宽须同时容下 meta 行（旧版只量标题，meta
    // 被截断成「2026年1...」，真机截图实证）；紧凑
    // 态 meta 不渲染、不计宽（Web display:none）。
    let compact = dockCompact
    let metaFont = Marks.dynFont(size: 10,
                                 style: .caption2)
    let metaW = compact ? 0 : metaLine.size(
        withAttributes: [.font: metaFont]).width
    // 最大宽按 Web 坞口径（线 2 #6）：坞左右各内缩
    // 62（= 页眉钮 46 + 外距 16，与 Web left/right
    // 62 同值），列态上限 = 坞宽 W−124；紧凑横排态
    // 再扣头像 72 + gap 8 → W−204。此前按 46+46+16
    // 算比 Web 宽 16，长标题胶囊会压到两侧钮。
    let chrome: CGFloat = compact ? 80 : 0
    let avail = measure.headerW > 0
        ? measure.headerW - 124 - chrome : 240
    // 定宽公式 = Web sync_width（title_contro-
    // ller.rs）：max(标题宽, meta 宽) + 内距 40
    // + 边框 1，钳 [66, avail]。Web 边框走
    // border-box 计入总宽；原生玻璃边框是
    // overlay 内描边、不占布局，边框 1 由公式
    // 侧补足，总宽与 Web 逐值一致（AUD-B-02
    // 对齐；旧 +40 漏计边框项）。算式单点在
    // 纯核心 TitleCapsuleLayout（与居中量测
    // 同源，fix_title_capsule_center），本处
    // 只备量测入参后委托，数值逐值不变。
    return CGFloat(TitleCapsuleLayout.capsuleWidth(
        titleW: Double(titleW), metaW: Double(metaW),
        avail: Double(avail)))
}

/// meta（Web 口径）：相对更新时间 · 正文字数。
private var metaLine: String {
    Lang.tf("editor.meta_line",
            ["ago": editor.item.ago,
             "n": String(editor.wordCount)])
}

}

    /// 背景色底表（Web BgSheet 口径）：8 色点 + 移除行。
    private var bgSheet: some View {
        // Web .bg-sheet 全度量：padding 20（底 = 20 +
        // 安全区）、head 居中（标题 20/700 tracking
        // -0.3、副 13 主色 70%、间距 4、head 下 16）、
        // 网格 gap 12、色点 44（选中 = 2px accent 边
        // + 20 号对勾）、移除区顶发丝线 + 居中两行
        // （图标 20 与 15/650 同行、注 11 次级色居其
        // 下）。容器形态（悬浮卡 + 进出场动画）在呈现
        // 段，见 body 的 bgSheet 呈现处。
        // 限高内滚（布局韧性批）：帧高 = min(实测内容
        // 高， 视口高 − 28），与 ••• 菜单 menuPanelH
        // 同机制（实测回写 + 首帧构成估高）；常态内
        // 容恒小于上限、形态逐值不变，矮高（横屏）×
        // 大字号组合下内容超限改内滚，不再顶出屏外
        // 裁掉表头。
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                Text(Lang.t("bg.title"))
                    .font(.system(size: f20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(T.textMain)
                Text(Lang.t("bg.sub"))
                    .font(.system(size: f13))
                    .foregroundStyle(
                        T.textMain.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            // 矮高（横屏 viewH < 500）改 8 列 1 行，
            // 省一行高约 56（审计 L-6）；横屏底表宽
            // 600、列宽 (560 − 7×12)/8 ≈ 59 ≥ 色点
            // 44，成立。
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible()),
                count: ui.viewH < 500 ? 8 : 4),
                      spacing: 12) {
                ForEach(Self.bgColors, id: \.self) { hex in
                    Button {
                        ui.beginBgClose(
                            apply: true, color: hex)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(T.colorOf(hex))
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(
                                    editor.bgColor == hex
                                        ? T.accent
                                        : T.dotBorder,
                                    lineWidth:
                                        editor.bgColor == hex
                                            ? 2 : 0.5))
                            if editor.bgColor == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: f20, weight: .semibold))
                                    .foregroundStyle(T.accent)
                            }
                        }
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
            .padding(.bottom, 16)
            if editor.bgColor != nil {
                // 移除区（Web .bg-remove-wrap 口径，
                // J2-F15）：边线前 margin-top 4、线后
                // padding-top 10（在 Button 上）。
                Rectangle()
                    .fill(T.borderSoft)
                    .frame(height: 0.5)
                    .padding(.top, 4)
                Button(role: .destructive) {
                    ui.beginBgClose(
                        apply: true, color: nil)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: f20))
                            Text(Lang.t("bg.remove"))
                                .font(.system(size: f15, weight: .semibold))
                                .tracking(-0.1)
                        }
                        Text(Lang.t("bg.note"))
                            .font(.system(size: f11))
                            .foregroundStyle(T.textSecondary)
                    }
                    .foregroundStyle(T.dangerBright)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle(radius: 16))
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20 + ui.safeBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(
            for: CGFloat.self
        ) { proxy in
            proxy.size.height
        } action: { newH in
            if abs(newH - ui.bgSheetH) > 0.5 {
                ui.bgSheetH = newH
            }
        }
        }
        .frame(height: min(
            ui.bgSheetH > 0
                ? ui.bgSheetH
                : (ui.viewH < 500 ? 240 : 300),
            max(0, ui.viewH - 28)))
        .overlayCard(radius: Radius.panel)
    }

    static let bgColors = ["#eaeef2", "#e8e0d4", "#d4e8d0",
                           "#d0e0e8", "#e8d0d4", "#fff3e0",
                           "#e8e0f0", "#f0e8d0"]

    // ••• 面板（Web .editor-menu-panel 度量：宽 246、radius
    // 22、浮层 overlay 档、行高 50、图标 accent）。条目 =
    // Web 六项口径、无分隔线（双栏开关仅宽屏显示，
    // iPhone 竖屏同 Web 的 display:none 不呈现；删除
    // 备忘项与分隔线已按用户 2026-11-26 裁定移除）。
    private var menuPanel: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    ui.showMenu = false
                    ui.showExport = false
                }
            if ui.showExport {
                exportPanel
                    .transition(.opacity)
            } else {
                // 面板限高（Web editor.css:1230：max-
                // height = 100dvh − safe − 64、超出滚
                // 动）：此前无上限，矮屏/横屏可溢出
                // （线 2 #25）。占位账：顶距 59 现行不
                // 变，可用高 = viewH − 59 − 8（底边距
                // 近似 Web −64 含 safe 的合成，横屏
                // 误差 ≤8，登记）；下限兜底 200。
                ScrollView(.vertical,
                           showsIndicators: false) {
                VStack(spacing: 0) {
                    if ui.wide {
                        twoPaneRow
                    }
                    menuItem(icon: "arrow.uturn.backward",
                             title: Lang.t("menu.undo"),
                             sub: Lang.t("menu.undo_sub"),
                             dimmed: !editor.canUndo) {
                        editor.undo()
                        ui.showMenu = false
                    }
                    menuItem(icon: "arrow.uturn.forward",
                             title: Lang.t("menu.redo"),
                             sub: Lang.t("menu.redo_sub"),
                             dimmed: !editor.canRedo) {
                        editor.redo()
                        ui.showMenu = false
                    }
                    // 附件行上距 4（Web layers.rs 内联
                    // margin-top:4px，J2-F06）。
                    menuItem(icon: "paperclip",
                             title: Lang.t("menu.attach"),
                             sub: Lang.t("menu.attach_sub"),
                             chevron: true) {
                        ui.showMenu = false
                        ui.showAttachChoice = true
                    }
                    .padding(.top, 4)
                    menuItem(icon: "square.and.arrow.up",
                             title: Lang.t("menu.export"),
                             sub: Lang.t("menu.export_sub"),
                             chevron: true) {
                        ui.showExport = true
                    }
                    // 背景行上距 4 + 图标紫（Web
                    // layers.rs 内联 margin-top:4px、
                    // palette stroke --color-purple，
                    // J2-F07/F08）。
                    menuItem(icon: "paintpalette",
                             title: Lang.t("menu.bg"),
                             sub: Lang.t("menu.bg_sub"),
                             chevron: true,
                             iconColor: T.purple) {
                        ui.showMenu = false
                        // 进场从出场态起播（Web sheet-wrap
                        // 首帧 is-closing 的等价处理）。
                        ui.bgClosing = true
                        ui.showBgSheet = true
                    }
                    .padding(.top, 4)
                }
                .padding(7)
                .frame(width: 246)
                .onGeometryChange(
                    for: CGFloat.self
                ) { proxy in
                    proxy.size.height
                } action: { newH in
                    if abs(newH - ui.menuPanelH) > 0.5 {
                        ui.menuPanelH = newH
                    }
                }
                }
                .frame(width: 246)
                // 面板高随内容（实测回写，与 slashPanelH
                // 同机制）：内容高与上限取小——旧
                // maxHeight 只是上限，ScrollView 在
                // ZStack 里被同级 Color.clear 撑满到上
                // 限，5 项内容悬空在近全屏面板上半
                // （截图四实证，fix_lift_spacing.md）。
                // 首帧估高 = 内距 14 + 项数 × 50 + 项
                // 间距 8（宽屏多一项双栏行）。
                .frame(height: min(
                    ui.menuPanelH > 0
                        ? ui.menuPanelH
                        : (ui.wide ? 322 : 272),
                    max(200, ui.viewH - 67)))
                .overlayCard()
                // 面板帧量测（U1 驱动 menuPanel
                // 面的 frame/renderedH 通道）：非
                // @Published 回写，不触发重演算。
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                ui.menuPanelFrame =
                                    geo.frame(
                                        in: .global)
                            }
                            .onChange(
                                of: geo.frame(
                                    in: .global)
                            ) { f in
                                ui.menuPanelFrame = f
                            }
                    }
                }
                .padding(.top, 59)
                .padding(.trailing, 16)
                .transition(.opacity)
            }
        }
        // 菜单 ↔ 导出面板切换（M14）：同浮层淡入切换。
        .animation(.easeInOut(duration: 0.18),
                   value: ui.showExport)
    }

    /// 导出面板（Web 口径）：返回钮 + 三格式行 + 尾注。
    private var exportPanel: some View {
        // 限高内滚（impl_dt_layout_resilience）：帧
        // 高 = min(实测内容高, 视口 − 67)，与 bgSheet
        // 同机制——矮高 × 大字号下自然高约 720 超出
        // 可视区且无从滚动；默认档恒低于上限、呈现
        // 逐值不变。定位内距（top 59 / trailing 16）
        // 仍在帧外、与呈现锚位无关。
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 0) {
            // 头（Web .export-head 口径）：min-height 46、
            // 返回钮 46×46 圆形玻璃钮、标题 15/650 居中
            // （右侧等宽占位补偿）、下边线 0.5。
            HStack(spacing: 0) {
                Button {
                    ui.showExport = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: f22,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: Radius.pill)
                }
                Text(Lang.t("export.title"))
                    .font(.system(size: f15, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: 46, height: 46)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 5)
            .frame(minHeight: 46)
            .overlay(alignment: .bottom) {
                Rectangle().fill(T.glassBorder)
                    .frame(height: 0.5)
            }
            // 选项列（Web .export-choices 口径，J2-F10）：
            // 行间 gap 3、列首顶距 6。
            VStack(spacing: 3) {
                exportChoice(badge: "MD", label: "Markdown",
                             detail: Lang.t("export.md_detail")) {
                    shareExported(editor.exportFile(
                        format: "md"))
                }
                exportChoice(badge: "<>", label: "HTML",
                             detail: Lang.t("export.html_detail")) {
                    shareExported(editor.exportFile(
                        format: "html"))
                }
                exportChoice(badge: "PDF", label: "PDF",
                             detail: Lang.t("export.pdf_detail")) {
                    ui.showMenu = false
                    ui.showExport = false
                    editor.exportPDF { url in
                        if let url { ui.shareURL = url }
                    }
                }
            }
            .padding(.top, 6)
            // 尾注（Web .export-note 口径，J2-F14）：
            // 10px/行高 1.45、外层 margin 5/4/2、内层
            // padding 9/5/2、顶线挂内层顶缘；文案为
            // iOS 口径改写（Web 原文是浏览器打印口径、
            // 不适用，已登记改判）。
            Text(Lang.t("export.pdf_file_note"))
                .font(.system(size: f10))
                .lineSpacing(f10 * 0.45)
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(.horizontal, 5)
                .padding(.top, 9)
                .padding(.bottom, 2)
                .overlay(alignment: .top) {
                    Rectangle().fill(T.glassBorder)
                        .frame(height: 0.5)
                }
                .padding(.horizontal, 4)
                .padding(.top, 5)
                .padding(.bottom, 2)
        }
        .padding(7)
        .onGeometryChange(
            for: CGFloat.self
        ) { proxy in
            proxy.size.height
        } action: { newH in
            if abs(newH - ui.exportPanelH) > 0.5 {
                ui.exportPanelH = newH
            }
        }
        }
        .frame(width: 246, height: min(
            ui.exportPanelH > 0 ? ui.exportPanelH : 300,
            max(160, ui.viewH - 67)))
        .overlayCard()
        .padding(.top, 59)
        .padding(.trailing, 16)
    }

    private func shareExported(_ url: URL?) {
        ui.showMenu = false
        ui.showExport = false
        if let url { ui.shareURL = url }
    }

    private func exportChoice(badge: String, label: String,
                              detail: String,
                              action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            // 行度量（Web panels.css 最终级联口径）：
            // min-height 54、padding 6/9、radius 14；徽
            // 章 34×34 透明无底、字体族 inherit（非
            // mono，panels.css:239-240 覆盖）、11（PDF
            // 小徽章 9）、tracking -0.2；label 14/650、
            // detail 11 且上距 2；chevron 19 强占位色
            // + 左距 4（J2-F11/F12/F13）。
            HStack(spacing: 11) {
                Text(badge)
                    .font(.system(size: badge == "PDF"
                        ? f9 : f11, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(T.accent)
                    // 徽章盒随徽章字同源缩放
                    // （impl_dt_layout_resilience）：定
                    // 尺寸 34 在大字号下「PDF」字宽溢出
                    // 盒外压标签——盒改 f34（caption2
                    // 同源、默认档恒 34）。
                    .frame(width: f34, height: f34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: f14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(detail)
                        .font(.system(size: f11))
                        .foregroundStyle(T.textSecondary)
                }
                Spacer()
                Text("›")
                    .font(.system(size: f19))
                    .foregroundStyle(T.placeholderStrong)
                    .padding(.leading, 4)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: 14))
    }

    private func menuItem(icon: String, title: String,
                          sub: String? = nil,
                          chevron: Bool = false,
                          dimmed: Bool = false,
                          danger: Bool = false,
                          iconColor: Color? = nil,
                          action: @escaping () -> Void)
        -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                // 度量（Web .menu-item 口径，J2-F03/F04/
                // F05）：高亮圆角 17、图标槽 24 内字形
                // 20、标题 tracking -0.1、副距 2。
                Image(systemName: icon)
                    // 字形封顶（impl_dt_layout_resilience）：
                    // title3 字形在大字号档达 ≈63pt、溢出
                    // 24 槽压住标题文字——封顶至槽宽 24，
                    // 槽与行几何不动、默认档逐值不变。
                    .font(.system(size: min(f20, 24)))
                    .foregroundStyle(danger ? T.danger
                                     : (iconColor ?? T.accent))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: f15, weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(danger ? T.danger
                                         : T.textMain)
                    if let sub {
                        Text(sub)
                            .font(.system(size: f11))
                            .foregroundStyle(T.textSecondary)
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: f18))
                        .foregroundStyle(
                            T.textSecondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.3 : 1)
        }
        .buttonStyle(RowPressStyle(radius: 17))
        // 置灰项仍可点（Web .dis 口径：点按关菜单、
        // 动作自身 no-op）——原先 .disabled 连关菜单
        // 都吞掉（线 2 #17）。
    }

    /// 正文区（单列/双栏分流；从 body 拆出以免
    /// 编译器类型检查超时）。
    @ViewBuilder
    private var contentArea: some View {
        Group {
        if ui.wide {
            wideColumns
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                scrollProbe
                ForEach(editor.blocks) { block in
                    BlockRow(editor: editor, block: block)
                }
                focusHotZone(slice: editor.blocks)
                backlinksSection
            }
            // 自检驱动注册（U4a）：滚动面锚点挂单
            // 列内容——宿主视图沿 superview 链即达
            // 编辑器 UIScrollView，驱动据此程序化
            // 滚动（EDT-06 紧凑坞变体）；scrollY
            // 读滚动状态对象（探针派生单源）。
            .background(UITestScrollAnchor {
                UITestSurfaceEntry(
                    id: "editor.scroll",
                    kind: "scroll", instance: "-",
                    state: [
                        "scrollY": {
                            "\(editor.scrollState.scrollY)"
                        },
                    ])
            })
            // 整页落焦占位账（单列）：上 padding 155 +
            // 下 40，内容高至少视口 − 195，热区弹性吸
            // 收余高至页底。0.9.48 起下距再加 ui.kbPad
            // （键盘落定遮挡量，内容对键盘安全区免疫
            // 后的等价补偿；无键盘时恒 0、账面不变）。
            .frame(minHeight: max(0, ui.viewH - 195),
                   alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 155)
            .padding(.bottom, 40 + ui.kbPad)
        }
        .coordinateSpace(name: "editorScroll")
        .scrollDismissesKeyboard(.interactively)
        }
        }
        .background(T.memoBg(editor.bgColor))
    }

    // ── 编辑页共享段（单列/双栏共用） ──────────────
    /// 滚动偏移回报：基线 = 当前形态下首个有效探针
    /// 值（捕获制）。守卫一：形态（单列/flow/
    /// independent）切换即作废重捕，防跨形态污染；
    /// 守卫二：单列/flow 下探针真实静止值远大于 0，
    /// 首帧的偏好默认值 0 不作数、防竞态锁错基线。
    /// 写入独立 scrollState，发布只失效页眉子树。
    private func updateScrollY(_ y: CGFloat) {
        let s = editor.scrollState
        let mode = ui.wide
            ? (editor.twoPaneIndependent ? 2 : 1) : 0
        if s.baseMode != mode {
            s.baseMode = mode
            s.baseY = nil
        }
        if s.baseY == nil {
            if mode != 2 && y == 0 { return }
            s.baseY = y
            DiagLog.shared.log(.info,
                "SCROLL base mode=\(mode) y=\(Int(y))")
        }
        let v = max(0, (s.baseY ?? y) - y)
        // SCROLL 轨迹（诊断）：探针原始值变化 ≥24pt
        // 且距上行 ≥0.3s 才记一行——一次滚动尝试的完
        // 整轨迹（起点/行程/是否回弹）据此定案。
        if s.traceY.isNaN
            || (abs(y - s.traceY) >= 24
                && Date().timeIntervalSince(s.traceAt) >= 0.3) {
            s.traceY = y
            s.traceAt = Date()
            DiagLog.shared.log(.info,
                "SCROLL y=\(Int(y)) base=\(Int(s.baseY ?? -1)) "
                + "v=\(Int(v))")
        }
        if v > s.maxScrollY { s.maxScrollY = v }
        if abs(v - s.scrollY) > 0.5 {
            s.scrollY = v
        }
    }

    /// 滚动偏移探针（页眉紧凑态口径）：1pt 哨兵 +
    /// onGeometryChange 直读坐标。旧路（0 高视图挂
    /// 背景 GeometryReader 发 preference）在真机恒
    /// 报 0——0.9.9/0.9.13 两版日志合证：base 永不
    /// 捕获、轨迹全灭、maxY 恒定——观测链整体换代。
    private var scrollProbe: some View {
        Color.clear
            .frame(height: 1)
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.frame(in: .named("editorScroll")).minY
            } action: { y in
                updateScrollY(y)
            }
    }

    /// 正文下方空白点按落焦（Web canvasFocusRoute +
    /// 用户 2026-11-23 定规：页眉/标题胶囊区以下整
    /// 页落焦、落点 = 点位所在栏的末可编辑文本块末
    /// 尾）。整页化口径：各形态内容 VStack 挂 frame
    /// (minHeight: 视口高 − 上下 padding 账) 撑满视
    /// 口，热区 minHeight 220 + 弹性吸收余高至页
    /// 底；点按即时落焦（原生手势无 Web 的位移门/
    /// 触摸回声问题，手势内同步兑现、等价更优）。
    /// slice = 本栏块切片；栏内无文本块回退全文末
    /// 文本块。
    private func focusHotZone(slice: [BlockState])
        -> some View {
        Color.clear
            .frame(minHeight: 220, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                let target = slice.last(where: { $0.isText })
                    ?? editor.blocks.last(where: {
                        $0.isText
                    })
                if let target {
                    editor.focusBlockId = target.id
                    editor.focusCaretEnd = true
                    DiagLog.shared.log(
                        .info,
                        "EDIT canvas focus -> \(target.id)")
                }
            }
    }

    /// 反向链接区（Web .wiki-backlinks 口径）：宽
    /// min(100%, 720)、上距 24、顶分隔线 1px + 内
    /// 距 14、标题 12/650 次级、列表 gap 2；行扁平
    /// ——min-height 44、padding 6/8、radius 10 命
    /// 中形、透明底、「↗」次级前缀、标题 link 色。
    @ViewBuilder
    private var backlinksSection: some View {
        if !ui.backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(T.borderSoft)
                    .frame(height: 1)
                Text(Lang.t("editor.backlinks"))
                    .font(.system(size: f12, weight: .semibold))
                    .foregroundStyle(T.textSecondary)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ui.backlinks) { memo in
                        Button {
                            DiagLog.shared.log(.info,
                                "WIKI backlink -> '\(memo.title)'")
                            onOpenMemo?(memo)
                        } label: {
                            HStack(spacing: 8) {
                                Text("↗")
                                    .font(.system(size: f14))
                                    .foregroundStyle(
                                        T.textSecondary)
                                Text(memo.title.isEmpty
                                     ? Lang.t("editor.untitled") : memo.title)
                                    .font(.system(size: f14))
                                    .foregroundStyle(T.linkBlue)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .contentShape(RoundedRectangle(
                                cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 24)
            .frame(maxWidth: 720, alignment: .leading)
        }
    }

    /// 一栏块列（双栏渲染单元）：栏尾恒挂本栏落焦热
    /// 区（解析本栏末文本块）；反向链接只挂文档末栏
    /// （showBacklinks）。minH > 0 时栏内容撑满栏高
    /// （independent 栏内独立滚动的整页落焦账）。
    @ViewBuilder
    private func blockColumn(_ range: Range<Int>,
                             minH: CGFloat = 0,
                             showBacklinks: Bool = false)
        -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(editor.blocks[range])) { block in
                // 宽屏行宽（Web 口径）：文本类块（段落/
                // 标题/引用/待办，含 MD 预览的段落底块）
                // 72ch ≈ 640 居中，媒体/卡满栏。
                let textual = block.isText
                    || block.type == "quote"
                BlockRow(editor: editor, block: block)
                    .frame(maxWidth: (ui.wide && textual)
                           ? 640 : .infinity)
                    .frame(maxWidth: .infinity,
                           alignment: .center)
            }
            focusHotZone(slice: Array(editor.blocks[range]))
            if showBacklinks {
                backlinksSection
            }
        }
        .frame(minHeight: minH, alignment: .top)
        .environment(\.wikiTap) { target in
            // MD 预览内 wiki 点按跳篇（与反向链接同通道）。
            // 跳转留痕（G12）：命中记行、未命中走 once
            // 防反复点按刷屏。
            if let m = editor.library.memo(
                forWikiTarget: target) {
                DiagLog.shared.log(.info,
                    "WIKI nav '\(target)' "
                    + "from \(editor.item.id) -> \(m.id)")
                onOpenMemo?(m)
            } else {
                DiagLog.shared.logOnce(
                    "wiki-miss:\(target)", .info,
                    "WIKI nav '\(target)' miss")
            }
        }
    }

    /// 宽屏判定同步（Web 媒体查询口径）：进入宽屏且为
    /// 独立模式时触发一次性落锚。
    private func syncWide(_ size: CGSize) {
        ui.viewW = size.width
        ui.viewH = size.height
        let w = (size.width >= 768 && size.height >= 600)
            || size.width >= 1100
        editor.columnsActive = w
        Marks.spreadWidth = w ? size.width : 0
        if w != ui.wide {
            ui.wide = w
            if w { editor.captureAnchorIfNeeded() }
        }
    }

    /// 双栏呈现（Web 口径）：恒两物理栏；flow 整页滚动
    /// + 规范分界，independent 锚分界 + 栏内独立滚动
    /// （栏高 = 视口余高，不照抄 Web 的 187px 页头数）。
    @ViewBuilder
    private var wideColumns: some View {
        let b = min(editor.columnBoundaryIndex,
                    editor.blocks.count)
        let n = editor.blocks.count
        // 栏距（Web editor.css 口径）：clamp(28, 3.2vw,
        // 52)，两模式同值。分隔线色走 --border-color
        // 档。线位分模式：flow 居中（两侧各 (gap-1)/2）；
        // independent 按 Web 栏内距（editor.css:
        // 1006-1011）——左栏 padding-right 16 + 左栏
        // 右缘 1px 线 + 栏间 gap + 右栏 padding-left
        // 16，内容净距 = gap + 32、线贴左栏右缘。
        let gap = min(52, max(28, ui.viewW * 0.032))
        let half = (gap - 1) / 2
        if editor.twoPaneIndependent {
            // 整页落焦占位账（independent）：外层上
            // padding 155 + 下 8 → 栏滚动视口高 =
            // viewH − 163；栏内容再扣自身底 padding
            // 24 → 栏 VStack minHeight = viewH − 187，
            // 两栏热区各自吸收本栏余高。
            let colMinH = max(0, ui.viewH - 187)
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        scrollProbe
                        // 左栏外层多探针 1 + 间距 6，
                        // minH 相应扣 7 保账平。
                        blockColumn(0..<b,
                                    minH: max(0, colMinH - 7),
                                    showBacklinks: b >= n)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24 + ui.kbPad)
                }
                .coordinateSpace(name: "editorScroll")
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(T.borderSoft)
                    .frame(width: 1)
                ScrollView {
                    blockColumn(b..<n, minH: colMinH,
                                showBacklinks: b < n)
                        .padding(.leading, gap + 15)
                        .padding(.bottom, 24 + ui.kbPad)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 155)
            .padding(.bottom, 8)
            .frame(maxWidth: 1440)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    scrollProbe
                    HStack(alignment: .top, spacing: 0) {
                        blockColumn(0..<b)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                        Rectangle()
                            .fill(T.borderSoft)
                            .frame(width: 1)
                            .padding(.horizontal, half)
                        blockColumn(b..<n)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                    }
                    // 栏下共享热区按栏几何分两半（与上
                    // 方栏列同构：等宽 + 1px 分隔 + half
                    // 横距），左右各解本栏末文本块；栏内
                    // 热区另覆盖高栏旁侧的矮栏空白。
                    HStack(alignment: .top, spacing: 0) {
                        focusHotZone(
                            slice: Array(editor.blocks[0..<b]))
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(T.borderSoft)
                            .frame(width: 1)
                            .padding(.horizontal, half)
                        focusHotZone(
                            slice: Array(editor.blocks[b..<n]))
                            .frame(maxWidth: .infinity)
                    }
                    backlinksSection
                }
                // 整页落焦占位账（flow）：上 padding
                // 155 + 下 24 → 内容高至少 viewH − 179。
                // 下距同单列加 ui.kbPad（0.9.48）。
                .frame(minHeight: max(0, ui.viewH - 179),
                       alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 155)
                .padding(.bottom, 24 + ui.kbPad)
                .frame(maxWidth: 1440)
            }
            .coordinateSpace(name: "editorScroll")
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// 双栏开关行（Web 菜单首行口径）：仅宽屏呈现。
    private var twoPaneRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.split.2x1")
                // 字形封顶（impl_dt_layout_resilience）：
                // 同 menuItem 口径，封顶至槽宽 24。
                .font(.system(size: min(f17, 24)))
                .foregroundStyle(T.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(Lang.t("menu.twopane"))
                    .font(.system(size: f14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(Lang.t("menu.twopane_sub"))
                    .font(.system(size: f11))
                    .foregroundStyle(T.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { editor.twoPaneIndependent },
                set: { _ in editor.toggleTwoPane() }))
                .labelsHidden()
                .tint(T.accent)
        }
        .padding(.horizontal, 10)
        // 双栏行自有度量（Web editor.css:896-935）：
        // min-height 56 / 标题 14，与普通菜单项的
        // 50/15 是两套——此前随 menuItem 取值偏小
        // （线 2 #22/#23）。
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

}

// ── gallery / 卡片 / 视频 / 附件块 ─────────────────
struct GalleryBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .title2)
    private var f22: CGFloat = 22

    var items: [[String: Any]] {
        (block.node["attrs"] as? [String: Any])?["items"]
            as? [[String: Any]] ?? []
    }

    /// 瓦身份 = 项身份（fix_image_card_load）：
    /// 旧形态 ForEach 按 offset 定身份，换图/删
    /// 项/排序后瓦内 ItemImageView 按位存续、图
    /// 随位置不随项。现以项的 fileId/url 为键，
    /// 同图重复添加以出现序消歧（删其一时另一
    /// 张键变 → 视图重建重载，图仍对——正确性
    /// 优先于该退化例的零重载）；无图项回落位
    /// 键（退化项、实际不可达）。
    struct GalleryTileEntry: Identifiable {
        let key: String
        var id: String { key }
        let ix: Int
        let item: [String: Any]
    }

    private var tileEntries: [GalleryTileEntry] {
        var seen: [String: Int] = [:]
        return items.enumerated().map { ix, it in
            let base: String
            if let fid = it["fileId"] as? String {
                base = "f:" + fid
            } else if let u = (it["url"] as? String)
                ?? (it["src"] as? String) {
                base = "u:" + u
            } else {
                base = "o:\(ix)"
            }
            let n = seen[base, default: 0]
            seen[base] = n + 1
            return GalleryTileEntry(
                key: n == 0 ? base : base + "#\(n)",
                ix: ix, item: it)
        }
    }

    /// 网格间距（Web .gallery-grid gap 4；空态
    /// .gallery-empty gap 6——旧实现两态同走 4，
    /// 与 Web 及自身注释均不符，fix_lift_spacing.md）。
    private var gridGap: CGFloat { items.isEmpty ? 6 : 4 }

    /// 瓦按位取角（内角规矩）：只有网格外轮廓四角
    /// 取 cardS、瓦与瓦的交界角一律直角（用户
    /// 2026-11-27 裁定，含 gallery）。
    private func tileCorners(_ ix: Int,
                             _ count: Int) -> CornerRect {
        let col = ix % 2, row = ix / 2
        let lastRow = (count - 1) / 2
        return CornerRect(
            tl: row == 0 && col == 0 ? Radius.cardS : 0,
            tr: row == 0 && col == 1 ? Radius.cardS : 0,
            bl: row == lastRow && col == 0
                ? Radius.cardS : 0,
            br: row == lastRow && col == 1
                ? Radius.cardS : 0)
    }

    var body: some View {
        // Web 口径：两列网格（间距 4）、瓦高固定 366
        // cover 裁切、圆角 22（线 1 #33——原先正方形
        // 瓦高差 200 量级）；点任一图进图片页；空图
        // 库出双占位瓦（高 366、gap 6、双底交替、标
        // 签随编辑态，#34）。
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: gridGap),
            GridItem(.flexible(), spacing: gridGap),
        ], spacing: gridGap) {
            if items.isEmpty {
                ForEach(0..<2, id: \.self) { ix in
                    tileCorners(ix, 2)
                        .fill(ix == 0 ? T.fillSubtle
                            : T.fillSubtle2)
                        .frame(height: 366)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .font(.system(size: f18))
                                    .opacity(ix == 0
                                        ? 0.4 : 0.3)
                                Text(ix == 0
                                    ? (editor.cardEditBlockId
                                        == block.id
                                        ? Lang.t("media.gallery_add")
                                        : Lang.t("media.gallery_add_hint"))
                                    : Lang.t("media.gallery_multi"))
                                    .font(.system(size: f11))
                                    .opacity(ix == 0
                                        ? 0.5 : 0.4)
                            }
                            .foregroundStyle(
                                T.textSecondary)
                        }
                        .onTapGesture {
                            // 编辑态点空瓦 = 加图（Web
                            // cardPick galleryAdd 同口径）。
                            if editor.cardEditBlockId
                                == block.id {
                                editor.galleryPickBlockId =
                                    block.id
                                editor.showGalleryAddPicker =
                                    true
                            }
                        }
                }
            }
            ForEach(tileEntries) { e in
                galleryTile(ix: e.ix, item: e.item)
            }
        }
        .clipShape(RoundedRectangle(
            cornerRadius: Radius.cardS))
        .background {
            // 拾起框：格网整体即视觉面（Web 标记面口
            // 径），半径 = 瓦圆角（Radius.cardS 同源）。
            if editor.draggingId == block.id {
                LiftFrame(faceRadius: Radius.cardS)
            }
        }
    }

    /// 单瓦：常态点瓦进图片页、编辑态点瓦换图（既
    /// 有口径不动）；F-14 编辑态增补——右上删项角
    /// 标（overlay 独立命中、不与瓦面点按叠触发）
    /// 与长按拖拽排序。排序不复用 DragPressEngine：
    /// 它是滚动视图级的块行引擎、注册表以块为粒
    /// 度、无瓦级概念，泛化它等于重写三轮根治过的
    /// 仲裁层；故走 onDrag/onDrop 独立轻量路，且编
    /// 辑态下本行块拾起已退场（BlockRow.dragAllowed），
    /// 同一长按触点无竞抢方。
    @ViewBuilder
    private func galleryTile(ix: Int,
                             item it: [String: Any]) -> some View {
        let editing = editor.cardEditBlockId == block.id
        let tile = GeometryReader { geo in
            ItemImageView(
                fileId: it["fileId"] as? String,
                urlString: (it["url"] as? String)
                    ?? (it["src"] as? String),
                library: editor.library)
                .frame(width: geo.size.width,
                       height: geo.size.height)
        }
        .frame(height: 366)
        .clipped()
        .clipShape(tileCorners(ix, items.count))
        .onTapGesture {
            if editor.cardEditBlockId == block.id {
                // 编辑态点图 = 换该张（Web
                // cardPick galleryItem 同口径）。
                editor.galleryPickBlockId = block.id
                editor.galleryReplaceIndex = ix
                editor.showGalleryReplacePicker =
                    true
            } else {
                editor.presentImagePage(
                    fileId: it["fileId"] as? String,
                    urlString: (it["url"] as? String)
                        ?? (it["src"] as? String),
                    name: it["name"] as? String)
            }
        }
        .overlay(alignment: .topTrailing) {
            if editing {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: f22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        .white, Color.black.opacity(0.55))
                    .padding(6)
                    .onTapGesture {
                        editor.applyGalleryRemove(
                            blockId: block.id, index: ix)
                    }
            }
        }
        if editing {
            tile
                .onDrag {
                    editor.galleryDragTileIndex = ix
                    return NSItemProvider(
                        object: "\(ix)" as NSString)
                }
                .onDrop(of: [.text],
                        delegate: GalleryTileDropDelegate(
                            target: ix, editor: editor,
                            blockId: block.id))
        } else {
            tile
        }
    }
}

/// 图库瓦拖拽排序的 drop 委托（F-14）：进入目标
/// 瓦即实时换位（跟随式），源位随换位链式跟进；
/// 落下收口排序会话（历史已在首动压栈）。载荷本
/// 身不读——源位经模型侧会话变量传递。
struct GalleryTileDropDelegate: DropDelegate {
    let target: Int
    let editor: EditorModel
    let blockId: String

    func dropEntered(info: DropInfo) {
        guard let src = editor.galleryDragTileIndex,
              src != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            editor.applyGalleryMove(blockId: blockId,
                                    from: src, to: target)
        }
        editor.galleryDragTileIndex = target
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        editor.endGalleryReorder()
        return true
    }
}

/// 音乐输入胶囊（Web MusicInputPill 口径）：单行 URL
/// 入口，粘出/回车即解析。原生以 TextField 承载（提示
/// 作文案占位，不入数据——Web 的 hint 是胶囊初始内容、
/// 提交时剥除，等价处理）。
struct MusicPillView: View {
    @ObservedObject var editor: EditorModel
    var block: BlockState
    @StateObject private var state = PillState()
    @FocusState private var fieldFocus: Bool
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14

    final class PillState: ObservableObject {
        @Published var text = ""
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: Binding(
                get: { state.text },
                set: { newValue in
                    state.text = newValue
                    // 粘入即检：含可提 URL 立即解析
                    // （Web 输入复检同口径）。
                    if EditorModel.extractCardURL(
                        newValue) != nil {
                        editor.submitMusicInput(
                            block, rawText: newValue)
                    }
                }),
                prompt: Text(Lang.t("media.music_paste_hint"))
                    .foregroundColor(T.textSecondary))
                .font(.system(size: f14))
                .foregroundStyle(T.textMain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .submitLabel(.go)
                .focused($fieldFocus)
                .onSubmit {
                    editor.submitMusicInput(
                        block, rawText: state.text)
                }
                .onChange(of: editor.focusMusicId) { id in
                    // 斜杠 musicCard 落点：焦点落胶囊本身。
                    if id == block.id {
                        fieldFocus = true
                        editor.focusMusicId = nil
                    }
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassControl(radius: Radius.pill)
    }
}

/// MD 预览渲染（E16）：core 解析树（serde 外部标签
/// JSON）→ SwiftUI。行内段先转 runs 字典走 Marks 既有
/// 标记管线（粗/斜/下划线/删除/行内码/链接）；高亮
/// ==…== 只渲正文 + highlight run（Web .moment-
/// highlight，二轮 E7）；行内公式走 MathML 快照附件
/// （MathImageStore，J1/E5），块级公式由 MdSegsView
/// 分段走 MdMathView。
enum MdRender {
    static func runs(_ segs: [Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        func push(_ text: String,
                  _ extra: [String: Any] = [:]) {
            guard !text.isEmpty else { return }
            var r: [String: Any] = ["text": text]
            for (k, v) in extra { r[k] = v }
            out.append(r)
        }
        func styled(_ v: Any, key: String) {
            for r in runs(v as? [Any] ?? []) {
                var r = r
                r[key] = true
                out.append(r)
            }
        }
        for s in segs {
            guard let d = s as? [String: Any],
                  let k = d.keys.first, let v = d[k]
            else { continue }
            switch k {
            case "Text": push(v as? String ?? "")
            case "Code": push(v as? String ?? "",
                              ["code": true])
            case "Strong": styled(v, key: "bold")
            case "Em": styled(v, key: "italic")
            case "Underline": styled(v, key: "underline")
            case "Del": push(v as? String ?? "",
                             ["strikethrough": true])
            case "Highlight":
                // 只渲正文（Web .moment-highlight）：
                // == 定界符不进呈现，底色/字重由
                // Marks 的 highlight run 兑现。
                push(v as? String ?? "",
                     ["highlight": true])
            case "Sup": push(v as? String ?? "",
                             ["sup": true])
            case "Sub": push(v as? String ?? "",
                             ["sub": true])
            case "Link":
                let lv = v as? [String: Any] ?? [:]
                let href = lv["href"] as? String ?? ""
                for r in runs(lv["children"] as? [Any]
                                ?? []) {
                    var r = r
                    r["_link"] = href
                    r["underline"] = true
                    out.append(r)
                }
            case "Wiki":
                let lv = v as? [String: Any] ?? [:]
                // target 经百分号编码才成合法 URL（中文
                // 标题裸拼会让 URL(string:) 失败、链接
                // 属性挂不上）。wiki 标记供 Marks 区分
                // 虚线下划线（J2-M01）。
                let enc = (lv["target"] as? String ?? "")
                    .addingPercentEncoding(
                        withAllowedCharacters:
                            .urlPathAllowed) ?? ""
                push(lv["label"] as? String ?? "",
                     ["_link": "wiki:" + enc, "wiki": true])
            case "FootRef":
                let lv = v as? [String: Any] ?? [:]
                push("\(lv["number"] as? Int ?? 0)",
                     ["sup": true])
            case "Math":
                // 行内公式（display 段由 MdSegsView 分
                // 段走块级）：tex 入 mathTex run，呈现
                // 由 Marks 的快照附件/失败红码兑现。
                let lv = v as? [String: Any] ?? [:]
                push(lv["tex"] as? String ?? "",
                     ["mathTex": lv["tex"] as? String ?? ""])
            case "Break": push("\n")
            default: break  // Image 由 MdSegsView 分段处理
            }
        }
        return out
    }

    static func attributed(_ segs: [Any], base: UIFont,
                           block: BlockState,
                           baseColor: UIColor = T.textMainUI)
        -> NSAttributedString {
        // 基准色随串构建（fix_dark_mode_full）：与
        // 承载 MdTextGroupView 的 textColor 同值同
        // 喂——textColor 通道不达 attributedText
        // 渲染（见 Marks.attributed 头注），串内显
        // 式前景才是真源。表格头调用点传
        // quoteTextUI 与其视图面同账。
        Marks.withRhythm(
            Marks.attributed(runs: runs(segs), base: base,
                             baseColor: baseColor),
            block: block)
    }

    /// 组是否需要交互：含链接（点按）或行内公式
    /// （附件）的组才开交互；无链无公式的组由承
    /// 载关交互，避免 UITextView 吞编辑块的长按
    /// 拾起/落焦手势（deepdive_inline_math 风险 1
    /// 缓解）。
    static func hasInteractive(_ segs: [Any]) -> Bool {
        runs(segs).contains {
            $0["_link"] != nil || $0["mathTex"] != nil
        }
    }
}

/// MD 预览内 wiki 点按通道（EditorView 注入、MdSegsView
/// 消费；环境值穿透 MdBlockView 递归层）。
private struct WikiTapKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var wikiTap: ((String) -> Void)? {
        get { self[WikiTapKey.self] }
        set { self[WikiTapKey.self] = newValue }
    }
}

/// MD 预览专用图（Web .markdown-render img 口径）：
/// max-width 100%、height auto（自然比例、不放
/// 大）、radius 10、margin 由组间 spacing 兑现。与
/// 编辑块 ItemImageView 分开——后者是填充裁切口
/// 径（封面共用），预览借用会裁切变形（二轮 E8）。
struct MdImageView: View {
    var urlString: String
    var library: Library
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if let img = loader.image {
                // 动图承载（AUD-D-01）：fit + 自然
                // 宽上限由 AnimImageView 复刻，GIF
                // 逐帧由 UIImageView 驱动。
                AnimImageView(image: img,
                              mode: .scaleAspectFit)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.mdImage))
            } else {
                RoundedRectangle(cornerRadius: Radius.mdImage)
                    .fill(T.fillSubtle)
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: loader.failed
                            ? "photo.badge.exclamationmark"
                            : "photo")
                            .foregroundStyle(T.textSecondary)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loader.load(fileId: nil, urlString: urlString,
                        library: library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
    }
}

/// MD 文本组承载（deepdive_inline_math 定性）：
/// SwiftUI Text 无 NSTextAttachment 渲染路径，
/// 行内公式附件穿 Text 必空白——只换承载不动
/// 上游，NSAttributedString（附件/段落节奏/链
/// 接全在内）喂只读 UITextView，TextKit 原生
/// 排附件。inset/padding 清零是与 SwiftUI Text
/// 布局盒对齐的关键（默认上下 8 + 行片段 5 不
/// 清会系统性多出偏移）。无链无公式的组关交互
/// （interactive=false），免吞编辑块长按拾起/
/// 落焦手势；MathImageStore version 通知经
/// MdSegsView 的 @ObservedObject 触发 body 重
/// 估 → updateUIView 换串，不另建通知。
struct MdTextGroupView: UIViewRepresentable {
    var attr: NSAttributedString
    var interactive: Bool
    var textColor: UIColor = T.textMainUI
    var onOpenURL: (URL) -> OpenURLAction.Result

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        // 字体类别自适应（fix_dynamic_type_follow）：
        // 纯字体面随类别自动缩放；attributed 串内的
        // 快照字体由 MdBlockView 的 hub 观察重建新串
        // 后经 updateUIView 换入。
        tv.adjustsFontForContentSizeCategory = true
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = nil
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = []
        tv.delegate = context.coordinator
        tv.textColor = textColor
        tv.isSelectable = interactive
        tv.isUserInteractionEnabled = interactive
        tv.attributedText = attr
        DiagLog.shared.logOnce(
            "md-textgroup-carrier", .info,
            "MD textgroup carrier uitextview")
        return tv
    }

    func updateUIView(_ tv: UITextView,
                      context: Context) {
        context.coordinator.parent = self
        tv.textColor = textColor
        tv.isSelectable = interactive
        tv.isUserInteractionEnabled = interactive
        if tv.attributedText != attr {
            tv.attributedText = attr
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UITextView,
                      context: Context) -> CGSize? {
        let w = proposal.width ?? .infinity
        let fit = uiView.sizeThatFits(
            CGSize(width: w, height: .infinity))
        return CGSize(width: w.isFinite ? w : fit.width,
                      height: fit.height)
    }

    final class Coordinator: NSObject,
        UITextViewDelegate {
        var parent: MdTextGroupView

        init(parent: MdTextGroupView) {
            self.parent = parent
        }

        // 链接点按全由 onOpenURL 闭包接管（wiki
        // 拦截语义在闭包内逐字保留），恒 false
        // 不让 UITextView 自行打开。
        func textView(_ textView: UITextView,
                      shouldInteractWith URL: URL,
                      in characterRange: NSRange,
                      interaction: UITextItemInteraction)
            -> Bool {
            let r = parent.onOpenURL(URL)
            DiagLog.shared.log(
                .info,
                "MD link tap \(URL.absoluteString) -> \(r)")
            return false
        }
    }
}

/// 行内段序列：文本段聚成组，Image 段独立成图、
/// display 公式独立成块（纵排）。
struct MdSegsView: View {
    var segs: [Any]
    var base: UIFont
    var block: BlockState
    var library: Library
    @Environment(\.wikiTap) private var wikiTap
    @Environment(\.openURL) private var openURL
    // 行内公式快照就绪通知：store 发布后重渲换图。
    @ObservedObject private var mathStore =
        MathImageStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(groups.enumerated()),
                    id: \.offset) { _, g in
                if let src = g.image {
                    MdImageView(urlString: src,
                                library: library)
                } else if let tex = g.math {
                    MdMathView(tex: tex)
                } else {
                    // 承载换只读 UITextView（附件穿
                    // SwiftUI Text 必空白，见
                    // MdTextGroupView 头注）；链接点
                    // 按闭包逐字承接原 OpenURLAction
                    // 语义：wiki 拦截 → wikiTap、余
                    // 由环境 openURL 执行系统打开
                    // （原 .systemAction 等价）。
                    MdTextGroupView(
                        attr: MdRender.attributed(
                            g.segs, base: base, block: block),
                        interactive: MdRender.hasInteractive(
                            g.segs),
                        onOpenURL: { url in
                            if url.scheme == "wiki" {
                                let t = String(
                                    url.absoluteString
                                        .dropFirst(5))
                                    .removingPercentEncoding
                                    ?? ""
                                wikiTap?(t)
                                return .handled
                            }
                            openURL(url)
                            return .handled
                        })
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }
            }
        }
    }

    private struct Group {
        var segs: [Any] = []
        var image: String?
        var math: String?
    }

    private var groups: [Group] {
        var out: [Group] = []
        var cur = Group()
        for s in segs {
            if let d = s as? [String: Any],
               let src = (d["Image"] as? [String: Any])?["src"]
                   as? String {
                if !cur.segs.isEmpty {
                    out.append(cur)
                    cur = Group()
                }
                out.append(Group(image: src))
            } else if let d = s as? [String: Any],
                      let mv = d["Math"] as? [String: Any],
                      mv["display"] as? Bool == true {
                // 段中 $$…$$（Web MathSpan display 分
                // 支）：独立成块居中呈现，与块级公式
                // 同路 MdMathView。
                if !cur.segs.isEmpty {
                    out.append(cur)
                    cur = Group()
                }
                out.append(Group(
                    math: mv["tex"] as? String ?? ""))
            } else {
                cur.segs.append(s)
            }
        }
        if !cur.segs.isEmpty { out.append(cur) }
        return out
    }
}

/// 解析树单块渲染（递归：Quote/Callout/List 子块）。
struct MdBlockView: View {
    var raw: Any
    var block: BlockState
    var library: Library
    /// 容器字号（线 1 #49/#51/#54）：引用/Callout 子
    /// 块 14、脚注子块 13，顶层 16；Para 与标题梯按
    /// 此缩放。
    var baseSize: CGFloat = 16
    /// 是否为预览顶层块（MdPreviewView 直子）：Web
    /// 宽屏段的 pre/引用/表格规则只命中顶层（选择
    /// 器 .md-preview.block > * 与 .editor-body >
    /// *），递归子块不带此标记。
    var topLevel = false
    /// 宽屏顶层判据：宽屏信号与 EditorView.syncWide
    /// 同源（Marks.spreadWidth）。
    private var wideTop: Bool {
        topLevel && Marks.spreadWidth > 0
    }
    // 字体代次观察（fix_dynamic_type_follow）：类
    // 别变更时本视图重演算，body 内的 dynFont 以
    // 新档重算、base 变化驱动 MdSegsView 重建
    // attributed 串（MdTextGroupView 随之换串）。
    @ObservedObject private var fontHub = FontHub.shared
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let name = raw as? String {
            // 单元变体（serde 外部标签为纯字符串）。
            if name == "Divider" {
                // 渐变线（同编辑块 #55；上下距在预览
                // spacing 之外以 padding 近似）。
                LinearGradient(
                    colors: [.clear, T.borderSoft, .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.vertical, 6)
            }
        } else if let d = raw as? [String: Any],
                  let k = d.keys.first, let v = d[k] {
            content(kind: k, v: v)
        }
    }

    @ViewBuilder
    private func content(kind k: String, v: Any)
        -> some View {
        let lv = v as? [String: Any] ?? [:]
        switch k {
        case "Heading":
            let level = lv["level"] as? Int ?? 2
            // 字号梯（tokens --md-heading-h1..h4 +
            // h5/h6 按审计口径 13/11），容器内按比例
            // 缩放；字重 .heavy 近似 750（#47）。
            let size: CGFloat = (level <= 1 ? 28
                : level == 2 ? 23
                : level == 3 ? 20
                : level == 4 ? 17
                : level == 5 ? 13 : 11) * baseSize / 16
            let style: UIFont.TextStyle = level <= 1 ? .title1
                : level == 2 ? .title2
                : level == 3 ? .title3
                : level == 4 ? .headline
                : level == 5 ? .subheadline : .footnote
            VStack(alignment: .leading, spacing: 0) {
                MdSegsView(
                    segs: lv["segs"] as? [Any] ?? [],
                    base: Marks.dynFont(
                        size: size, weight: .heavy,
                        style: style),
                    block: block, library: library)
                if level <= 1 && baseSize == 16 {
                    // H1 下边线（#47，同编辑标题口径）。
                    Rectangle()
                        .fill(T.borderSoft)
                        .frame(height: 1)
                        .padding(.top, 7)
                }
            }
        case "Para":
            MdSegsView(segs: lv["segs"] as? [Any] ?? [],
                       base: Marks.dynFont(size: baseSize),
                       block: block, library: library)
        case "Code":
            Text(lv["code"] as? String ?? "")
                .font(.system(size: f13, design: .monospaced))
                .lineSpacing(7.8)
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(.vertical, wideTop ? 10 : 12)
                .padding(.horizontal, wideTop ? 12 : 14)
                .background(T.codeBg,
                            in: RoundedRectangle(
                                cornerRadius: Radius.block))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.block)
                        .strokeBorder(T.borderSoft,
                                      lineWidth: 1)
                }
        case "Math":
            MdMathView(tex: lv["tex"] as? String ?? "")
        case "Quote":
            // Web blockquote 口径（#49/#50）：子块字
            // 号 14、文距盒左缘 3+14=17、左 3px 条贴
            // 盒边、三边 1px 描边、padding 上下 10。
            // 宽屏顶层（审计 L-8，Web 宽屏段 block-
            // quote padding 9/12）：纵 9、左 = 条 3
            // + 12 = 15、右 12。
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(
                    (lv["blocks"] as? [Any] ?? [])
                        .enumerated()), id: \.offset) {
                    _, sub in
                    MdBlockView(raw: sub, block: block,
                                library: library,
                                baseSize: 14)
                }
            }
            .padding(.vertical, wideTop ? 9 : 10)
            .padding(.leading, wideTop ? 15 : 17)
            .padding(.trailing, wideTop ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T.quoteBg,
                        in: RoundedRectangle(
                            cornerRadius: Radius.quote))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.quote)
                    .strokeBorder(T.borderSoft, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(T.quoteBar)
                    .frame(width: 3)
            }
        case "Callout":
            MdCalloutView(
                style: lv["style"] as? String ?? "note",
                title: lv["title"] as? String ?? "",
                folding: lv["folding"] as? String,
                blocks: lv["blocks"] as? [Any] ?? [],
                block: block, library: library)
        case "List":
            let ordered = lv["ordered"] as? Bool ?? false
            let start = lv["start"] as? Int ?? 1
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(
                    (lv["items"] as? [Any] ?? [])
                        .enumerated()), id: \.offset) {
                    idx, itemAny in
                    let item = itemAny as? [String: Any]
                        ?? [:]
                    // 文起点（J2-M09）：非任务支 HStack
                    // 间距 = Web padding-left（ul 1.2em /
                    // ol 1.4em，按容器字号缩放）− 标记框
                    // markerW，基字 16 时为 1.2/4.4；任务
                    // 勾选支维持 8 不动。小字号容器下钳 0。
                    // 标记框（impl_dt_layout_resilience）：
                    // markerW = 1.125em（基字 16 时 = 旧
                    // 定值 18、逐值不变）——旧定宽 18 在
                    // 字号放大时两位数标记溢出框外，现框
                    // 宽随 baseSize 同源缩放、文起点 em
                    // 账恒成立。
                    let isTask = item["checked"] != nil
                    // em 账基字与同行正文同档（fix_
                    // dynamic_type_follow）：正文经
                    // dynFont 按类别缩放，此前标记字/
                    // markerW/文起点用未缩放 baseSize、
                    // 类别变更后与正文脱档；现以工厂缩
                    // 放基字立账（默认档 = baseSize、
                    // 逐值不变，em 账恒成立）。
                    let scaledBase = FontFactory.scaledSize(
                        baseSize, style: .body)
                    let markerW = scaledBase * 1.125
                    HStack(alignment: .top,
                           spacing: isTask ? 8
                               : max(0, (ordered ? 1.4 : 1.2)
                                     * scaledBase - markerW)) {
                        if let checked = item["checked"]
                            as? Bool {
                            Image(systemName: checked
                                ? "checkmark.square.fill"
                                : "square")
                                .font(.system(size: f15))
                                // 未选标记与编辑面同走
                                // checkBorder 单源（Web
                                // MD 与编辑面同一 checkbox
                                // 令牌；此前误用 text-
                                // Secondary——浅值近似不可
                                // 见、深值分叉，fix_dark_
                                // mode_full 归令）。
                                .foregroundStyle(checked
                                    ? T.checkChecked
                                    : T.checkBorder)
                        } else {
                            Text(ordered
                                 ? "\(start + idx)."
                                 : "•")
                                .font(.system(size: scaledBase))
                                .foregroundStyle(T.textMain)
                                .frame(width: markerW,
                                       alignment: .trailing)
                        }
                        VStack(alignment: .leading,
                               spacing: 4) {
                            MdSegsView(
                                segs: item["segs"] as? [Any]
                                    ?? [],
                                base: Marks.dynFont(
                                    size: baseSize),
                                block: block,
                                library: library)
                            ForEach(Array(
                                (item["sub"] as? [Any] ?? [])
                                    .enumerated()),
                                    id: \.offset) { _, sub in
                                MdBlockView(
                                    raw: sub, block: block,
                                    library: library,
                                    baseSize: baseSize)
                            }
                        }
                    }
                }
            }
        case "Table":
            let head = lv["head"] as? [[Any]] ?? []
            let rows = lv["rows"] as? [[[Any]]] ?? []
            let aligns = lv["align"] as? [Int] ?? []
            // Web table 口径（editor.css:2-16，J2-M04）：
            // 横滚、宽 max-content（min 160）、--card-bg
            // 底、1px --border-color 边、radius 12；th
            // 12/600 --md-text-muted、cell 横 pad 12、
            // 纵 9、td max-width 18rem=288、列对齐按
            // align、行间分隔。字号更正（规格 §三.4 裁
            // 定并入本项）：table 字号 14、td 无独立覆
            // 盖继承 14——原生旧值 16 系 audit2 #53 误
            // 读，本项一并改 14。宽屏顶层（审计 L-8，
            // Web 宽屏段）：th/td min-width 5rem=80、
            // cell pad 改纵 7 横 9。
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading,
                     horizontalSpacing: 0,
                     verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(head.enumerated()),
                                id: \.offset) { ci, cell in
                            MdTextGroupView(
                                attr: MdRender.attributed(
                                    cell,
                                    base: Marks.dynFont(
                                        size: 12,
                                        weight: .semibold),
                                    block: block,
                                    baseColor: T.quoteTextUI),
                                interactive:
                                    MdRender.hasInteractive(cell),
                                textColor: T.quoteTextUI,
                                onOpenURL: { url in
                                    openURL(url)
                                    return .handled
                                })
                                .frame(minWidth: wideTop
                                           ? 80 : nil,
                                       maxWidth: 288,
                                       alignment: tableAlign(
                                           aligns, ci))
                                .padding(.horizontal,
                                         wideTop ? 9 : 12)
                                .padding(.vertical,
                                         wideTop ? 7 : 9)
                        }
                    }
                    Divider().gridCellColumns(
                        max(1, head.count))
                    ForEach(Array(rows.enumerated()),
                            id: \.offset) { ri, row in
                        GridRow {
                            ForEach(Array(row.enumerated()),
                                    id: \.offset) { ci, cell in
                                MdTextGroupView(
                                    attr: MdRender.attributed(
                                        cell,
                                        base: Marks.dynFont(
                                            size: 14),
                                        block: block),
                                    interactive:
                                        MdRender.hasInteractive(
                                            cell),
                                    onOpenURL: { url in
                                        openURL(url)
                                        return .handled
                                    })
                                    .frame(minWidth: wideTop
                                               ? 80 : nil,
                                           maxWidth: 288,
                                           alignment:
                                               tableAlign(
                                                   aligns, ci))
                                    .padding(.horizontal,
                                             wideTop ? 9 : 12)
                                    .padding(.vertical,
                                             wideTop ? 7 : 9)
                            }
                        }
                        if ri < rows.count - 1 {
                            Divider()
                                .gridCellColumns(
                                    max(1, head.count))
                        }
                    }
                }
                .frame(minWidth: 160, alignment: .leading)
                .background(T.cardBg,
                            in: RoundedRectangle(
                                cornerRadius: Radius.block))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.block)
                        .strokeBorder(T.borderSoft,
                                      lineWidth: 1)
                }
                .clipShape(RoundedRectangle(
                    cornerRadius: Radius.block))
            }
        case "Footnotes":
            // Web 口径（#54）：字 13、--text-secondary、
            // 上边 1px 线、项距 0.2em。
            VStack(alignment: .leading, spacing: 10) {
                Rectangle()
                    .fill(T.borderSoft)
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(
                        (lv["items"] as? [Any] ?? [])
                            .enumerated()), id: \.offset) {
                        idx, itemAny in
                        let item = itemAny as? [String: Any]
                            ?? [:]
                        HStack(alignment: .top, spacing: 6) {
                            // 标签按序号呈现（内部 id 不
                            // 出画，与正文 FootRef 的
                            // number 同源）。
                            Text("\(idx + 1).")
                                .font(.system(size: f13))
                                .foregroundStyle(
                                    T.textSecondary)
                            VStack(alignment: .leading,
                                   spacing: 4) {
                                ForEach(Array(
                                    (item["blocks"] as? [Any]
                                        ?? []).enumerated()),
                                        id: \.offset) {
                                    _, sub in
                                    MdBlockView(
                                        raw: sub, block: block,
                                        library: library,
                                        baseSize: 13)
                                }
                                // 回链（Web .footnote-
                                // backlinks 口径，J2-M02）：
                                // 按 core 的 ref_ids 逐个
                                // 出 ↩，32×32 命中盒、link
                                // 色、行 gap 4、左距 0.35em
                                // （13 号字 ≈ 4.6）。点击跳
                                // 转为动作子项存疑（预览整
                                // 块点按回源码、无锚点滚动
                                // 面），此处只落视觉形态。
                                let refIds = item["ref_ids"]
                                    as? [String] ?? []
                                if !refIds.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(Array(
                                            refIds.enumerated()),
                                                id: \.offset) {
                                            _, _ in
                                            Text("↩")
                                                .font(.system(size: f13))
                                                .foregroundStyle(
                                                    T.linkBlue)
                                                .frame(width: 32,
                                                       height: 32)
                                        }
                                    }
                                    .padding(.leading, 4.6)
                                }
                            }
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func tableAlign(_ aligns: [Int], _ ci: Int)
        -> Alignment {
        switch aligns.indices.contains(ci) ? aligns[ci] : 0 {
        case 1: return .center
        case 2: return .trailing
        default: return .leading
        }
    }
}

/// MD Callout（折叠兑现）：folding 为 "-"/"+" 时标题
/// 行可开合（"-" 默认收起、"+" 默认展开），无折叠符
/// 恒展开；开合只动呈现、正文点按仍由预览层回源码。
struct MdCalloutView: View {
    var style: String
    var title: String
    var folding: String?
    var blocks: [Any]
    var block: BlockState
    var library: Library
    @StateObject private var state = CalloutState()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15

    private final class CalloutState: ObservableObject {
        @Published var open: Bool?
    }

    private var isOpen: Bool {
        state.open ?? (folding != "-")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                if folding != nil {
                    // M28：箭头旋转 0.16s（Web summary
                    // ::after transition 口径）。
                    withAnimation(.easeInOut(duration: 0.16)) {
                        state.open = !isOpen
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: f18,
                                      weight: .semibold))
                        .foregroundStyle(
                            T.calloutAccent(style))
                    Text(title)
                        .font(.system(size: f15, weight: .bold))
                        .foregroundStyle(T.textMain)
                    if folding != nil {
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: f11, weight: .semibold))
                            .foregroundStyle(
                                T.calloutAccent(style))
                            .rotationEffect(.degrees(
                                isOpen ? 180 : 0))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(folding == nil)
            if isOpen {
                ForEach(Array(blocks.enumerated()),
                        id: \.offset) { _, sub in
                    MdBlockView(raw: sub, block: block,
                                library: library,
                                baseSize: 14)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.calloutBg(style),
                    in: RoundedRectangle(
                        cornerRadius: Radius.block))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.block)
                .strokeBorder(T.borderSoft, lineWidth: 1)
        }
    }

    private var icon: String {
        switch style {
        case "tip": return "lightbulb.fill"
        case "warning": return "exclamationmark.triangle.fill"
        case "important": return "exclamationmark.circle.fill"
        case "caution": return "exclamationmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }
}

/// 行内公式快照库（J1/E5，Web .math-inline 的原生
/// 等价）：core MathML（FFI renderMathml display=
/// false）经隐藏 WKWebView 排版后快照成图；JS 量
/// 测宽/高/基线——strut 法（零尺寸 inline-block 以
/// baseline 对齐、其顶边与 math 顶边的差即基线位
/// 置，下沉量 = 高 − 基线）；按 (字号×2, 明暗,
/// tex) 缓存、串行单 webview 逐个处理。就绪/失败
/// 经 @Published version 通知预览面重渲（MdSegs-
/// View 观察 shared）。失败 = FFI 空串或量测/快
/// 照失败 → 调用方回退红色原码（.math-source）。
/// S13 附着点：公式预热 guard 步名 OpsStep
/// .mathPreheat 已登记——现无预热调用（entry 懒
/// 加载、webview 首用才建）；将来新增预热必须先
/// 查 OpsDirectives.cached().isDisabled(该步名)。
final class MathImageStore: NSObject, ObservableObject,
    WKNavigationDelegate {
    static let shared = MathImageStore()

    enum Entry {
        case ready(UIImage, descent: CGFloat)
        case failed
        case pending
    }

    @Published private(set) var version = 0
    private var entries: [String: Entry] = [:]
    private var queue: [(key: String, tex: String,
                         size: CGFloat, dark: Bool)] = []
    private var busy = false
    private var webView: WKWebView?
    private var currentKey: String?

    func entry(tex: String, fontSize: CGFloat) -> Entry {
        let dark = UITraitCollection.current
            .userInterfaceStyle == .dark
        let key = "\(Int(fontSize * 2))|\(dark ? 1 : 0)|\(tex)"
        if let e = entries[key] { return e }
        if currentKey != key
            && !queue.contains(where: { $0.key == key }) {
            queue.append((key: key, tex: tex,
                          size: fontSize, dark: dark))
            pump()
        }
        return .pending
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        let ml = renderMathml(tex: job.tex, display: false)
        guard !ml.isEmpty else {
            entries[job.key] = .failed
            DiagLog.shared.logOnce(
                "math-inline-fail:\(job.key)", .warn,
                "MATH inline render failed '\(job.tex)'")
            version += 1
            pump()
            return
        }
        busy = true
        currentKey = job.key
        let wv = ensureWebView()
        wv.overrideUserInterfaceStyle = job.dark
            ? .dark : .light
        wv.loadHTMLString(Self.html(ml, size: job.size),
                          baseURL: nil)
    }

    private func ensureWebView() -> WKWebView {
        if let wv = webView { return wv }
        let wv = WKWebView(frame: CGRect(
            x: -4000, y: -4000, width: 900, height: 300))
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.navigationDelegate = self
        // 离屏挂载（快照需要渲染树）：挂关键窗口、移
        // 出可视区，不入任何页面层级。
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let win = scenes.flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
            ?? scenes.flatMap { $0.windows }.first
        win?.addSubview(wv)
        webView = wv
        return wv
    }

    private static func html(_ ml: String,
                             size: CGFloat) -> String {
        """
        <meta name="viewport" content="width=device-width, \
        initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; font-size: \(size)px; }
        math { font-size: 1em; }
        </style>
        <span id="mnstrut" style="display:inline-block; \
        width:0; height:0; vertical-align:baseline"></span>\(ml)
        """
    }

    private func finishCurrent(_ entry: Entry?) {
        guard let key = currentKey else { return }
        entries[key] = entry ?? .failed
        if entry == nil {
            DiagLog.shared.logOnce(
                "math-inline-fail:\(key)", .warn,
                "MATH inline snapshot failed")
        }
        version += 1
        busy = false
        currentKey = nil
        pump()
    }

    func webView(_ webView: WKWebView,
                 didFinish navigation: WKNavigation!) {
        guard let key = currentKey else { return }
        let js = """
        (() => { const m = document.querySelector('math');
        const s = document.getElementById('mnstrut');
        if (!m || !s) return null;
        const r = m.getBoundingClientRect();
        const b = s.getBoundingClientRect();
        return {x: r.x, y: r.y, w: r.width, h: r.height,
                base: b.top - r.top}; })()
        """
        webView.evaluateJavaScript(js) { [weak self] res, _ in
            guard let self, self.currentKey == key else {
                return
            }
            func num(_ d: [String: Any], _ k: String)
                -> CGFloat? {
                (d[k] as? NSNumber).map {
                    CGFloat($0.doubleValue)
                }
            }
            guard let d = res as? [String: Any],
                  let x = num(d, "x"), let y = num(d, "y"),
                  let w = num(d, "w"), let h = num(d, "h"),
                  let base = num(d, "base"),
                  w > 0, h > 0 else {
                self.finishCurrent(nil)
                return
            }
            let descent = min(max(h - base, 0), h)
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(x: x, y: y, width: w,
                              height: h)
            webView.takeSnapshot(with: cfg) { img, _ in
                guard self.currentKey == key else { return }
                if let img {
                    self.finishCurrent(
                        .ready(img, descent: descent))
                } else {
                    self.finishCurrent(nil)
                }
            }
        }
    }

    func webView(_ webView: WKWebView,
                 didFail navigation: WKNavigation!,
                 withError error: Error) {
        finishCurrent(nil)
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation
                     navigation: WKNavigation!,
                 withError error: Error) {
        finishCurrent(nil)
    }
}

/// 块级公式：core render_mathml 过 FFI 出 MathML，
/// WKWebView 渲染（透明底、随明暗配色、高度回读）；
/// 渲染失败（空串）回退红色源码（Web .math-source
/// 失败态语义）。
final class MathHeightBox: ObservableObject {
    @Published var height: CGFloat = 28
}

struct MdMathView: View {
    var tex: String
    @StateObject private var box = MathHeightBox()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14

    var body: some View {
        let ml = renderMathml(tex: tex, display: true)
        if ml.isEmpty {
            Text(tex)
                .font(.system(size: f14, design: .monospaced))
                .foregroundStyle(T.mathFail)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
        } else {
            MathWebView(mathml: ml, box: box)
                .frame(height: box.height)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MathWebView: UIViewRepresentable {
    var mathml: String
    var box: MathHeightBox

    final class Coordinator: NSObject, WKNavigationDelegate {
        var box: MathHeightBox
        init(_ b: MathHeightBox) { box = b }
        func webView(_ webView: WKWebView,
                     didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(
                "document.body.scrollHeight") { r, _ in
                if let h = r as? CGFloat, h > 0 {
                    DispatchQueue.main.async {
                        if abs(self.box.height - (h + 4)) > 0.5 {
                            self.box.height = h + 4
                        }
                    }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(box)
    }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = .clear
        // 横滚开（Web .math-block overflow-x auto）：
        // 长公式可达；纵向由高度回读恰容、不滚。此
        // 前禁滚动把长公式截断不可达（二轮 E6）。
        wv.scrollView.isScrollEnabled = true
        wv.scrollView.showsHorizontalScrollIndicator = false
        wv.scrollView.showsVerticalScrollIndicator = false
        wv.navigationDelegate = context.coordinator
        wv.loadHTMLString(html, baseURL: nil)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}

    private var html: String {
        """
        <meta name="viewport" content="width=device-width, \
        initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; font-size: 16px; }
        .mnwrap { width: max-content; min-width: 100%; \
        margin: 0 auto; padding: 2px 0; \
        box-sizing: border-box; text-align: center; }
        math { font-size: 1em; }
        </style>
        <div class="mnwrap">\(mathml)</div>
        """
    }
}

/// MD 源段落的预览面：整块点按回源码编辑。
struct MdPreviewView: View {
    @ObservedObject var editor: EditorModel
    var block: BlockState
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    /// 标题块的额外顶距（#46，J2-M07 补满）：标题
    /// margin-top 1.25em 按各级字号（28/23/20/17）
    /// 折净距 35/28.75/25/21.25，段下距 0.65em=10.4
    /// 被其压过；预览统一 spacing 10 之上按级补差
    /// 25/18.75/15/11.25（首块不补）。
    private func headingExtraTop(_ raw: Any, _ idx: Int)
        -> CGFloat {
        guard idx > 0, let d = raw as? [String: Any],
              let hv = d["Heading"] as? [String: Any]
        else { return 0 }
        let level = hv["level"] as? Int ?? 2
        return level <= 1 ? 25 : level == 2 ? 18.75
            : level == 3 ? 15 : level == 4 ? 11.25 : 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if editor.mdBlocks(for: block).isEmpty {
                // 解析为空（如全文是未被引用的定义行）：
                // 原文兜底呈现，避免空白块被误认内容
                // 丢失（审计 D-R1；Web 有原文兜底）。
                Text(block.text)
                    .font(.system(size: f16))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
            }
            ForEach(Array(editor.mdBlocks(for: block)
                .enumerated()), id: \.offset) { idx, raw in
                MdBlockView(raw: raw, block: block,
                            library: editor.library,
                            topLevel: true)
                    .padding(.top,
                             headingExtraTop(raw, idx))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { editor.beginMdEdit(block) }
    }
}

struct CardBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @Environment(\.openURL) private var openURL
    // M30：减弱动态效果时骨架不脉冲（恒常态）。
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @StateObject private var pulse = PulseState()

    final class PulseState: ObservableObject {
        @Published var on = false
    }

    var library: Library { editor.library }

    // 卡数据在 node 顶层 url + meta{title,subtitle,cover,
    // source}（core 口径）；attrs 读法只对旧形兜底。
    var meta: [String: Any] {
        block.node["meta"] as? [String: Any] ?? [:]
    }
    var cardURL: String {
        (block.node["url"] as? String) ?? ""
    }
    var status: String {
        block.node["status"] as? String ?? ""
    }
    var isMusic: Bool { block.type == "musicCard" }
    var title: String { meta["title"] as? String ?? "" }
    var cover: String {
        let c = (meta["cover"] as? String)
            ?? (meta["image"] as? String) ?? ""
        if c.hasPrefix("data:") { return c }
        let u = EditorModel.extractCardURL(c) ?? ""
        // mzstatic 封面归一（Web proxy_img 同口径）：
        // Apple 的 og 图是带大面积透明留白的画布、艺
        // 术图只占中心一小块（他平台为紧图、独 Apple
        // 中招，用户实证）；尺寸段改 600x600bb 取紧
        // 方图后再满幅裁切。
        if u.contains("mzstatic.com") {
            return u.replacingOccurrences(
                of: #"\d+x\d+bb\."#,
                with: "600x600bb.",
                options: .regularExpression)
        }
        return u
    }
    var host: String {
        guard let u = URL(string: cardURL),
              let h = u.host else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    var body: some View {
        // 面型判别收口 CardFace.derive 单点（补丁
        // 债偿还批二 A-2）：本 switch 只按面型选
        // 子视图，判别序不在此重写（旧 if 链与拾
        // 起面派生各持一份判据的形态已退役）。
        Group {
            switch block.cardFace {
            case .fileRow:
                // 带 fileId 的音乐卡 = 音频附件，走文件行。
                fileRow
            case .skeleton:
                skeleton
            case .errorCard:
                errorCard
            case .inputPill:
                // input 胶囊（Web 状态机同位：标题判
                // 定之前；批 K F7——此前无此分支，
                // input 态音乐块整块隐形）。行分发已
                // 先行把 input 态送 MusicPillView，本
                // 支为卡视图本体被直达时的同面兜底。
                inputPill
            case .readyCard:
                readyCard
            case .errCard:
                errCard
            case .urlPill:
                urlPill
            case .emptyPill:
                // 空态胶囊（Web 状态机末支；批 K
                // F7——此前落 EmptyView 整块隐形）。
                // 此支只达音乐卡（链接卡已被 errCard
                // 截走、有 URL 已被 urlPill 截走）。
                emptyPill
            case .singleImage, .plainNote:
                // 附件专属面型，音乐/链接卡派生不达。
                EmptyView()
            }
        }
    }

    // ── ready 卡（Web .link-card-block 口径） ──────
    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !cover.isEmpty {
                // 封面整幅出血（Web .lkc-cover 口径）：
                // 2.4:1 盒定几何、图满幅 cover、直角
                // （卡面裁外角）。
                GeometryReader { geo in
                    ItemImageView(fileId: nil,
                                  urlString: cover,
                                  library: library)
                        .frame(width: geo.size.width,
                               height: geo.size.height)
                }
                .aspectRatio(2.4, contentMode: .fit)
                // 封面子面按位取角（贴顶只圆上角、
                // 与正文交界直角，内角规矩）。
                .clipShape(CornerRect(tl: Radius.cardL,
                                      tr: Radius.cardL))
                .background(T.borderSoft)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: f14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineSpacing(f14 * 0.4)
                    .lineLimit(2)
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.system(size: f12))
                        .foregroundStyle(T.textSecondary)
                        .lineSpacing(f12 * 0.3)
                        .lineLimit(2)
                        .padding(.top, 3)
                }
                sourceRow
                    .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, cover.isEmpty ? 10 : 6)
            .padding(.bottom, 12)
        }
        .contentCard(radius: Radius.cardL)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    private var subtitleText: String {
        // 副标题只认 meta.subtitle（Web 口径，description
        // 不兜底）；哔哩哔哩链接卡不显示副标题。
        let s = meta["subtitle"] as? String ?? ""
        if !isMusic, isBilibili { return "" }
        return s
    }

    /// 哔哩哔哩判定（Web is_bilibili 全式，批 K
    /// F10）：所示来源 == 哔哩哔哩，或 type=video
    /// 且 URL 含 bilibili/b23.tv——此前只判来源，
    /// 来源为空、host 兜底 b23.tv 的视频卡会多显
    /// 一行副标题。sourceText 与 Web shown_source
    /// 同链（source→siteName→host）。
    private var isBilibili: Bool {
        if sourceText == "哔哩哔哩" { return true }
        guard (meta["type"] as? String) == "video"
        else { return false }
        return cardURL.contains("bilibili")
            || cardURL.contains("b23.tv")
    }

    private var sourceText: String {
        if isMusic {
            let s = meta["source"] as? String ?? ""
            return s.isEmpty ? Lang.t("media.music") : s
        }
        let s = (meta["source"] as? String)
            ?? (meta["siteName"] as? String) ?? ""
        return s.isEmpty ? host : s
    }

    private var sourceIcon: String {
        if isMusic { return "music.note" }
        switch meta["type"] as? String {
        case "music": return "music.note"
        case "video": return "play.rectangle"
        default: return "link"
        }
    }

    private var sourceRow: some View {
        HStack(spacing: 5) {
            Image(systemName: sourceIcon)
                .font(.system(size: f12))
            Circle()
                .fill(T.textSecondary.opacity(0.4))
                .frame(width: 3, height: 3)
            Text(sourceText)
                .font(.system(size: f11))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(T.textSecondary)
    }

    // ── link-card 无标题 err 卡（Web 口径） ────────
    private var errCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(host.isEmpty ? cardURL : host)
                .font(.system(size: f14, weight: .semibold))
                .foregroundStyle(T.textMain)
                .lineLimit(2)
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: f12))
                Circle()
                    .fill(T.textSecondary.opacity(0.4))
                    .frame(width: 3, height: 3)
                Text(cardURL)
                    .font(.system(size: f11))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.textSecondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(radius: Radius.cardL)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    // ── 音乐 loading 骨架（封面 + 三行，整体脉冲） ──
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 骨架封面子面按位取角（贴顶只圆上角、
            // 交界直角，内角规矩）。
            CornerRect(tl: Radius.cardL, tr: Radius.cardL)
                .fill(T.borderSoft)
                .aspectRatio(2.4, contentMode: .fit)
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.75,
                               height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.50,
                               height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(T.borderSoft)
                        .frame(width: geo.size.width * 0.35,
                               height: 12)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .contentCard(radius: Radius.cardL)
        .opacity(pulse.on ? 0.55 : 1)
        .onAppear {
            // M22 脉冲周期对齐 Web（1.4s ease-in-out
            // alternate，此前 0.7 单程快了一倍）。M30：
            // 减弱动态效果时不启动脉冲。
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4)
                    .repeatForever(autoreverses: true)) {
                    pulse.on = true
                }
            }
        }
    }

    // ── 音乐 error 卡（图标 + URL + 重试钮） ───────
    private var errorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: f20))
                .foregroundStyle(T.textMain)
            // URL 本身可点开（Web error 卡锚口径，
            // 批 K F8）：openCard 内含 http(s) 前缀
            // 闸，与 Web safe_http_url 白名单降级
            // 等价（不过闸则点按无动作）；卡面其余
            // 部分不挂手势（Web cursor default）。
            Text(cardURL)
                .font(.system(size: f14))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { openCard() }
            Button {
                var n = block.node
                n["status"] = "loading"
                block.node = n
                block.nodeVersion += 1
                editor.scheduleSave()
                editor.startResolveCard(block)
            } label: {
                Text(Lang.t("media.retry"))
                    .font(.system(size: f13, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(T.fillHoverStrong,
                                in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentCard(radius: Radius.cardL)
    }

    // ── 音乐 input 胶囊（Web .music-input-pill：───
    // padding 12/18、radius 999、glass-control 底、
    // 14 号主色、纯文本无图标） ───────────────────
    private var inputPill: some View {
        Text(Lang.t("media.music_paste_hint"))
            .font(.system(size: f14))
            .foregroundStyle(T.textMain)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassControl(radius: Radius.pill)
    }

    // ── 音乐空态胶囊（Web .music-pill：图标 17 + ──
    // 点击粘贴提示，padding 12/16、glass-content
    // 底；Web 为纯呈现 div、无点按行为） ──────────
    private var emptyPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: f17))
                .foregroundStyle(T.textMain)
            Text(Lang.t("media.music_click_hint"))
                .font(.system(size: f14))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentCard(radius: Radius.pill)
    }

    // ── 音乐兜底胶囊（有 URL 无标题/状态） ─────────
    // Web 同支口径（批 K F9）：URL 常显，status=
    // error 时其后并列注记（media.preview_unavail-
    // able 语言键）——此前以硬编码「预览不可用」
    // 替换 URL 文本，链接本体不可见。
    private var urlPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: f17))
                .foregroundStyle(T.textMain)
            Text(cardURL)
                .font(.system(size: f14))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            if status == "error" {
                Text(Lang.t("media.preview_unavailable"))
                    .font(.system(size: f11))
                    .foregroundStyle(T.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentCard(radius: Radius.pill)
        .contentShape(Rectangle())
        .onTapGesture { openCard() }
    }

    // ── 音频附件文件行 ───────────────────────────
    @StateObject private var shareState = ShareState()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17
    @ScaledMetric(relativeTo: .title3)
    private var f20: CGFloat = 20

    private var fileRow: some View {
        let name = library.attachmentName(for: block.fileId)
            ?? (block.node["name"] as? String)
            ?? (block.node["title"] as? String)
            ?? Lang.t("media.audio")
        return AttachmentRow(icon: "music.note", name: name,
                             hint: Lang.t("media.music"),
                             wide: editor.columnsActive)
            .contentShape(Rectangle())
            .onTapGesture {
                if let fid = block.fileId {
                    shareAttachmentFile(
                        library: library, state: shareState,
                        fid: fid, name: name)
                }
            }
            .sheet(isPresented: Binding(
                get: { shareState.url != nil },
                set: { if !$0 { shareState.url = nil } })) {
                if let url = shareState.url {
                    ShareSheet(
                        url: url,
                        onComplete: shareState.shareCompletion)
                }
            }
    }

    private func openCard() {
        let s = cardURL
        guard s.hasPrefix("http://") || s.hasPrefix("https://"),
              let u = URL(string: s) else { return }
        openURL(u)
    }
}

final class VideoHolder: ObservableObject {
    @Published var player: AVPlayer?
    /// 已备源键（fix_image_card_load 键控化）：
    /// prepare 按当前源键比对，键变重备、同键
    /// 且 player 在位才跳过——取代旧 `player ==
    /// nil` 一次性守卫（fid 后到/换片永不重备）。
    var preparedKey: String?
    /// 自然比例（AUD-D-04）：Web <video> 宽
    /// 100%、高随内在比例（.blk-media 无比例
    /// 钳），旧形态块面恒 16:9 与之分叉（竖屏
    /// 视频信箱化）。prepare 备源后异步读轨道
    /// 自然尺寸回填，未定/读不到恒 16:9 兜底。
    @Published var aspect: CGFloat = 16 / 9
    /// 失败态（AUD-D-04）：空字节/坏 URL/写盘
    /// 失败/播放项异步失败旧形态恒呈待播占位、
    /// 与加载中不可分辨；现与 Diag 结果行成对
    /// 上屏（备源键变即复位）。
    @Published var failed = false
    /// 播放项失败观察句柄：键变重备时随新项
    /// 替换（旧句柄释放即注销观察）。
    var itemObservation: NSKeyValueObservation?
}

/// 内嵌播放器面（本工具链 AVKit 的 SwiftUI VideoPlayer
/// 不可见，改用 AVPlayerViewController 承载，与 Web
/// <video controls> 等价）。
struct InlinePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(
        context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(
        _ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// 视频块（Web 口径）：整幅视频面内嵌播放器（原生
/// VideoPlayer 即 Web <video controls> 的等价更优形
/// 态），自然比例（AUD-D-04：未定前 16:9 兜底）、
/// 圆角 22；备源/播放失败呈失败面、不再恒占位。
struct VideoBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @StateObject private var holder = VideoHolder()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .largeTitle)
    private var f40: CGFloat = 40

    var body: some View {
        Group {
            if holder.failed {
                RoundedRectangle(cornerRadius: Radius.cardS)
                    .fill(T.borderSoft)
                    .aspectRatio(holder.aspect,
                                 contentMode: .fit)
                    .overlay {
                        Image(systemName:
                            "video.badge.exclamationmark")
                            .font(.system(size: f40))
                            .foregroundStyle(T.textSecondary)
                    }
            } else if let player = holder.player {
                InlinePlayerView(player: player)
                    .aspectRatio(holder.aspect,
                                 contentMode: .fit)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.cardS))
            } else {
                RoundedRectangle(cornerRadius: Radius.cardS)
                    .fill(T.borderSoft)
                    .aspectRatio(holder.aspect,
                                 contentMode: .fit)
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: f40))
                            .foregroundStyle(T.textSecondary)
                    }
            }
        }
        .onAppear { prepare() }
        // 源键变化重备（fix_image_card_load）：
        // 与图片面同病根治——块视图不重建时靠钩
        // 子再呈 prepare，键控在 prepare 内单点。
        .onChange(of: block.fileId) { _ in prepare() }
        .onChange(of: block.imageURL) { _ in prepare() }
    }

    private func prepare() {
        let key: String?
        if let s = (block.node["url"] as? String)
            ?? block.imageURL {
            key = "u:" + s
        } else if let fid = block.fileId {
            key = "f:" + fid
        } else {
            key = nil
        }
        if holder.preparedKey == key,
           holder.player != nil { return }
        holder.preparedKey = key
        holder.player = nil
        // 键变重备复位（AUD-D-04）：比例回 16:9
        // 兜底、失败态清、旧项观察随新项替换。
        holder.aspect = 16 / 9
        holder.failed = false
        holder.itemObservation = nil
        guard let key else {
            DiagLog.shared.logOnce(
                "video:nosource", .info,
                "VIDEO prepare nosource（视频块无源）")
            return
        }
        if let s = (block.node["url"] as? String)
            ?? block.imageURL {
            guard let u = URL(string: s) else {
                // 静默出口一（AUD-E-05②）：URL 串
                // 在而不可解析——旧形态无痕无播放，
                // 现记结果行；批 3 起同步上失败面
                // （AUD-D-04）。
                DiagLog.shared.log(.warn,
                    "VIDEO prepare badurl key=\(key)")
                holder.failed = true
                return
            }
            let item = AVPlayerItem(url: u)
            holder.player = AVPlayer(playerItem: item)
            watchItem(item, key: key)
            resolveAspect(asset: AVURLAsset(url: u),
                          key: key)
            return
        }
        if let fid = block.fileId {
            let lib = library
            DispatchQueue.global(qos: .userInitiated).async {
                let data = lib.attachmentData(fid)
                // 静默出口二（AUD-E-05②）：附件缺
                // 失/空数据——旧形态照建 player 指
                // 空文件、播放死而无痕；现不建
                // player + 记行；批 3 起同步上失败
                // 面（AUD-D-04：空字节无失败态）。
                guard !data.isEmpty else {
                    DiagLog.shared.log(.warn,
                        "VIDEO prepare missing "
                        + "fid=\(fid) bytes=0")
                    DispatchQueue.main.async {
                        guard holder.preparedKey == key
                        else { return }
                        holder.failed = true
                    }
                    return
                }
                // 临时名扩展名（AUD-D-04）：旧形态
                // 恒名 .mov——按附件 MIME（清单类
                // 型面）派生真扩展名，派生不出回
                // .mov 兜底（播放按内容嗅探、名仅
                // 作提示，不影响可播性）。
                let ext = UTType(
                    mimeType: lib.attachmentTypes[fid]
                        ?? "")?
                    .preferredFilenameExtension ?? "mov"
                let path = NSTemporaryDirectory()
                    + "video-\(fid).\(ext)"
                do {
                    try data.write(
                        to: URL(fileURLWithPath: path))
                } catch {
                    // 静默出口三（AUD-E-05②）：写盘
                    // 失败——旧形态 try? 吞错、player
                    // 指不存在文件；现记行收口；批
                    // 3 起同步上失败面。
                    DiagLog.shared.log(.error,
                        "VIDEO prepare write "
                        + "fid=\(fid) -> error \(error)")
                    DispatchQueue.main.async {
                        guard holder.preparedKey == key
                        else { return }
                        holder.failed = true
                    }
                    return
                }
                DispatchQueue.main.async {
                    // 在途期间键已变（换片）则弃。
                    guard holder.preparedKey == key
                    else { return }
                    let url = URL(
                        fileURLWithPath: path)
                    let item = AVPlayerItem(url: url)
                    holder.player = AVPlayer(
                        playerItem: item)
                    watchItem(item, key: key)
                    resolveAspect(
                        asset: AVURLAsset(url: url),
                        key: key)
                }
            }
        }
    }

    /// 自然比例回填（AUD-D-04）：异步读视频轨
    /// 自然尺寸（计 preferredTransform 旋转）回
    /// 主线程落 holder.aspect；在途期间键已变
    /// 则弃、读不到保持 16:9 兜底。
    private func resolveAspect(asset: AVAsset,
                               key: String) {
        let target = holder
        asset.loadValuesAsynchronously(
            forKeys: ["tracks"]) {
            var resolved: CGFloat?
            if let track = asset.tracks(
                withMediaType: .video).first {
                let size = track.naturalSize.applying(
                    track.preferredTransform)
                if size.height != 0 {
                    resolved = abs(size.width)
                        / abs(size.height)
                }
            }
            DispatchQueue.main.async {
                guard target.preparedKey == key,
                      let resolved, resolved > 0
                else { return }
                target.aspect = resolved
            }
        }
    }

    /// 播放项失败观察（AUD-D-04）：URL 源的
    /// 404/坏数据在 AVPlayerItem 异步转 failed，
    /// prepare 当场无从知——观察其 status，失
    /// 败即上失败面 + 记行（与备源失败同面）；
    /// 观察句柄存 holder、键变重备时替换注销。
    private func watchItem(_ item: AVPlayerItem,
                           key: String) {
        let target = holder
        holder.itemObservation = item.observe(
            \.status, options: [.new]
        ) { [weak target] item, _ in
            guard item.status == .failed,
                  let target else { return }
            DispatchQueue.main.async {
                guard target.preparedKey == key
                else { return }
                target.failed = true
                DiagLog.shared.log(.warn,
                    "VIDEO play failed key=\(key)")
            }
        }
    }
}

final class ShareState: ObservableObject {
    @Published var url: URL?
    /// 本次分享的结局回调：share 发起方在设 url 前
    /// 一并写入，sheet 构建时透传 ShareSheet（批 K
    /// F4 的 ATT 结局打点通道）。
    var shareCompletion: ((Bool, Error?) -> Void)?
}

/// 附件分享发起（Web open_js_file 同口径，批 K
/// F4 单一实现，附件文件行与音频文件行共用）：
/// 字节为空 = 附件缺失——记 ATT missing 且不弹
/// 面（此前照样写出空文件弹分享面）；写盘失败
/// 记 ATT error、不弹面（此前 try? 吞错照弹）；
/// 弹面结局经完成回调记 shared/cancelled/error
/// （此前全程无打点）。
func shareAttachmentFile(library: Library,
                         state: ShareState,
                         fid: String, name: String) {
    DispatchQueue.global(qos: .userInitiated).async {
        let data = library.attachmentData(fid)
        guard !data.isEmpty else {
            DiagLog.shared.log(.warn,
                "ATT open \(fid) -> missing")
            return
        }
        let type = library.attachmentTypes[fid] ?? ""
        let meta = name
            + (type.isEmpty ? "" : " " + type)
            + " \(data.count)B"
        let safe = name.replacingOccurrences(
            of: "/", with: "_")
        let path = NSTemporaryDirectory() + safe
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            DiagLog.shared.log(.error,
                "ATT open \(fid) \(meta) "
                + "-> error \(error)")
            return
        }
        DispatchQueue.main.async {
            state.shareCompletion = { completed, error in
                if let error {
                    DiagLog.shared.log(.error,
                        "ATT open \(fid) \(meta) "
                        + "-> error \(error)")
                } else {
                    DiagLog.shared.log(.info,
                        "ATT open \(fid) \(meta) -> "
                        + (completed ? "shared"
                                     : "cancelled"))
                }
            }
            state.url = URL(fileURLWithPath: path)
        }
    }
}

/// 附件文件行（Web .attachment-file 口径）：内边距
/// 16/20、图标 26、名 14 中粗单行省略、右侧提示胶囊
/// （11 号次级字 + 强悬停底 + 2/10 内边距）。
struct AttachmentRow: View {
    var icon: String
    var name: String
    var hint: String
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .title2)
    private var f24: CGFloat = 24
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    /// 宽屏（spread）度量切换（Web 口径）：padding
    /// 14/12、gap 8；常态 20/16、gap 10。半径同走
    /// 宽屏变值：editor.css:726 宽屏段 .attachment-
    /// file 为 --radius-22（特异性 (0,3,0) 胜基础
    /// 32），经 Radius.attachmentFile 派生（S1「恒
    /// 32」裁断已被组版复核实证推翻，见 release_
    /// 0.9.54.md S1 节与 fix_attachment_radius_
    /// wide.md）。
    var wide: Bool = false

    var body: some View {
        HStack(spacing: wide ? 8 : 10) {
            Image(systemName: icon)
                .font(.system(size: f24))
                .foregroundStyle(T.textMain)
            Text(name)
                .font(.system(size: f14, weight: .medium))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(hint)
                .font(.system(size: f11))
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(T.fillHoverStrong, in: Capsule())
        }
        .padding(.horizontal, wide ? 14 : 20)
        .padding(.vertical, wide ? 12 : 16)
        .contentCard(radius: Radius.attachmentFile(wide: wide))
    }
}

struct AttachmentBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var shareState = ShareState()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14

    var library: Library { editor.library }

    /// 文件行名单（fid, 显示名）：名 = 清单名优先、
    /// 节点名兜底、再 fid（Web 文件行口径——清单是
    /// 文件名真值源，节点名是导入时的快照）。判图
    /// 统一走 MemoItem.attIsImage（清单 MIME 优先、
    /// 名扩展兜底，含 svg/avif）——旧本地扩展名表
    /// （缺 svg/avif、无 MIME 面）已退役。
    var files: [(String, String)] {
        let attrs = block.node["attrs"] as? [String: Any] ?? [:]
        func displayName(_ fid: String,
                         _ nodeName: String?) -> String {
            library.attachmentNames[fid] ?? nodeName ?? fid
        }
        if let items = attrs["items"] as? [[String: Any]] {
            return items.compactMap { it in
                guard let fid = it["fileId"] as? String
                else { return nil }
                return (fid, displayName(
                    fid, it["name"] as? String))
            }
        }
        if let fid = attrs["fileId"] as? String {
            return [(fid, displayName(
                fid, attrs["name"] as? String))]
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if block.cardFace == .singleImage,
               let first = files.first {
                // 图片附件（node.image）：整幅图呈现，圆角
                // 32，点按进图片页（Web 口径）。
                ItemImageView(fileId: first.0,
                              urlString: nil,
                              library: library)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.cardL))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editor.presentImagePage(
                            fileId: first.0, urlString: nil,
                            name: first.1)
                    }
            } else {
                ForEach(files, id: \.0) { fid, name in
                    AttachmentRow(
                        icon: "paperclip",
                        name: name, hint: Lang.t("list.open"),
                        wide: editor.columnsActive)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 图片类文件进图片页，其余走
                            // 分享（Web 文件行分发口径）：
                            // 判图走 attIsImage 单一口径
                            // （清单 MIME 优先、svg/avif
                            // 在名扩展集内）。
                            if MemoItem.attIsImage(
                                name: name,
                                type: library
                                    .attachmentTypes[fid]) {
                                editor.presentImagePage(
                                    fileId: fid,
                                    urlString: nil,
                                    name: name)
                            } else {
                                shareAttachmentFile(
                                    library: library,
                                    state: shareState,
                                    fid: fid, name: name)
                            }
                        }
                }
                if files.isEmpty {
                    Text(Lang.t("media.att_none"))
                        .font(.system(size: f14))
                        .foregroundStyle(T.textSecondary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareState.url != nil },
            set: { if !$0 { shareState.url = nil } })) {
            if let url = shareState.url {
                ShareSheet(
                    url: url,
                    onComplete: shareState.shareCompletion)
            }
        }
    }

    // 单图判别（Web 口径：node.image == true 的单
    // 文件附件整幅呈现、多文件仍走文件行）已收口
    // CardFace.derive 单点（补丁债偿还批二 A-2：
    // body 首支以 cardFace == .singleImage 判），
    // 本地单图私有判别已删。
}

struct ImgTextBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var ui = ImgTextUI()
    @StateObject private var loader = ImageLoader()
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .title2)
    private var f24: CGFloat = 24
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13

    final class ImgTextUI: ObservableObject {
        @Published var editing = false
        @Published var draft = ""
    }

    var body: some View {
        Group {
            if block.type == "imgTextCard" {
                // Web .img-text-card 口径：圆角 22 内容
                // 卡，上图（整幅、高上限 468）下文（内边
                // 距 12/14、14 号、行高 1.7）。
                VStack(alignment: .leading, spacing: 0) {
                    if block.fileId != nil
                        || block.imageURL != nil {
                        if let img = loader.image {
                            // 整幅出血、直角（卡面裁外
                            // 角）：自然高、上限 468 裁切。
                            Color.clear
                                .aspectRatio(
                                    img.size.width
                                        / max(img.size.height,
                                              1),
                                    contentMode: .fit)
                                .frame(maxHeight: 468)
                                .overlay {
                                    // 动图承载（AUD-D-01）：
                                    // fill 语义由 AnimImage-
                                    // View 复刻、GIF 逐帧由
                                    // UIImageView 驱动。
                                    AnimImageView(
                                        image: img,
                                        mode: .scaleAspectFill)
                                }
                                // 图区子面按位取角（贴顶
                                // 只圆上角、与文交界直角，
                                // 内角规矩）。
                                .clipShape(CornerRect(
                                    tl: Radius.cardS,
                                    tr: Radius.cardS))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    tapImageArea()
                                }
                        } else {
                            // 加载占位子面按位取角（贴
                            // 顶只圆上角、交界直角）。
                            CornerRect(tl: Radius.cardS,
                                       tr: Radius.cardS)
                                .fill(T.fillSubtle)
                                .frame(height: 160)
                        }
                    } else {
                        Text(Lang.t("media.add_image"))
                            .font(.system(size: f13))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 160)
                            .background(T.fillSubtle)
                            // 空占位子面按位取角（贴顶
                            // 只圆上角）：真机实证无显
                            // 式裁切时底角呈圆、与文条
                            // 交界露白缺口（截图三，内
                            // 角规矩 fix_lift_spacing.md）。
                            .clipShape(CornerRect(
                                tl: Radius.cardS,
                                tr: Radius.cardS))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tapImageArea()
                            }
                    }
                    textLabel
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .contentCard(radius: Radius.cardS)
            } else {
                // Web .img-text-row 口径：左图占半幅整高、
                // 右文 10/14 内边距、14 号行高 1.7、最多
                // 6 行；整卡高 181–196。
                GeometryReader { geo in
                    HStack(spacing: 10) {
                        if block.fileId != nil
                            || block.imageURL != nil {
                            if let img = loader.image {
                                // 图区整幅出血、直角（卡面
                                // 裁外角），占半幅整高。动图
                                // 承载换 AnimImageView
                                // （AUD-D-01）。
                                AnimImageView(
                                    image: img,
                                    mode: .scaleAspectFill)
                                    .frame(
                                        width: geo.size.width
                                            * 0.5,
                                        height: geo.size
                                            .height)
                                    // 图半子面按位取角（贴
                                    // 左只圆左角、与文半交
                                    // 界直角，内角规矩）。
                                    .clipShape(CornerRect(
                                        tl: Radius.cardS,
                                        bl: Radius.cardS))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        tapImageArea()
                                    }
                            } else {
                                // 加载占位子面按位取角
                                // （贴左只圆左角）。
                                CornerRect(tl: Radius.cardS,
                                           bl: Radius.cardS)
                                    .fill(T.pressBg)
                                    .frame(
                                        width: geo.size.width
                                            * 0.5)
                            }
                        } else {
                            ZStack {
                                Rectangle()
                                    .fill(T.fillSubtle)
                                Image(systemName: "photo")
                                    .font(.system(size: f24))
                                    .foregroundStyle(
                                        T.textSecondary
                                            .opacity(0.3))
                            }
                            .frame(width: geo.size.width
                                * 0.5)
                            // 空占位子面按位取角（贴
                            // 左只圆左角、交界直角）。
                            .clipShape(CornerRect(
                                tl: Radius.cardS,
                                bl: Radius.cardS))
                        }
                        textLabel
                            .lineLimit(6)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            // 文本盒整高、文贴顶（Web
                            // .itr-text 口径）：旧实现
                            // 文块在半幅内垂直居中、上
                            // 下留白悬空（截图一实证，
                            // fix_lift_spacing.md）。
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity,
                                   alignment: .topLeading)
                    }
                }
                .frame(height: 188)
                .contentCard(radius: Radius.cardS)
            }
        }
        .onAppear {
            loader.load(fileId: block.fileId,
                        urlString: block.imageURL,
                        library: editor.library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        // 源键变化重呈 loader（fix_image_card_
        // load）：建卡时无图、点图区经 replace 流
        // 塞 fid——靠此钩 + 闸门键控当场出图，旧
        // 形态图区恒灰占位。
        .onChange(of: block.fileId) { _ in
            loader.load(fileId: block.fileId,
                        urlString: block.imageURL,
                        library: editor.library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .onChange(of: block.imageURL) { _ in
            loader.load(fileId: block.fileId,
                        urlString: block.imageURL,
                        library: editor.library,
                        maxPixel: MediaDecode.blockMaxPixel)
        }
        .onChange(of: block.imgTextEditSignal) { _ in
            ui.draft = block.text
            ui.editing = true
        }
        .sheet(isPresented: Binding(
            get: { ui.editing },
            set: { ui.editing = $0 })) {
            NavigationStack {
                TextEditor(text: Binding(
                    get: { ui.draft },
                    set: { ui.draft = $0 }))
                    .padding(12)
                    .navigationTitle(Lang.t("sheet.imgtext_title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(Lang.t("action.cancel")) { ui.editing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Lang.t("action.save")) {
                                block.node["text"] = ui.draft
                                block.text = ui.draft
                                editor.scheduleSave()
                                ui.editing = false
                            }
                        }
                    }
            }
        }
    }

    private func openImagePage() {
        editor.presentImagePage(
            fileId: block.fileId, urlString: block.imageURL,
            name: block.node["name"] as? String)
    }

    /// 图区点按分流（Web card-editing 口径）：编辑态
    /// 点图区 = 换图（cardPick kind=set）；常态有图
    /// 进图片页、无图不动作（占位文案即引导走编辑态）。
    private func tapImageArea() {
        if editor.cardEditBlockId == block.id {
            editor.replaceImageBlockId = block.id
            editor.showReplacePicker = true
        } else if block.fileId != nil || block.imageURL != nil {
            openImagePage()
        }
    }

    private var textLabel: some View {
        Text(block.text.isEmpty ? Lang.t("sheet.view_full") : block.text)
            .font(.system(size: f14))
            .lineSpacing(f14 * 0.7)
            .foregroundStyle(block.text.isEmpty
                ? T.textSecondary : T.textMain)
            .frame(minHeight: 44, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                ui.draft = block.text
                ui.editing = true
            }
    }
}

// ── 设计令牌（与 Web tokens.css 逐值对齐，明暗双写） ──
enum T {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? dark : light)
        })
    }
    static var bg: Color { dyn(0xF2F2F7, 0x000000) }
    /// 根背景 UIColor 变体（与 bg 同值）：根色是
    /// 全应用唯一背景色源（背景层级模型）；本变
    /// 体供 memoBgUI 无底色时回落与 UIKit 侧取色。
    static var bgUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0x000000 : 0xF2F2F7)
        }
    }
    static var textMain: Color { dyn(0x1A1A1A, 0xFFFFFF) }
    static var textSecondary: Color { dyn(0x68686D, 0x98989D) }
    /// 玻璃控件标签色（Web --glass-label-color
    /// #48494F/#D1D1D6）：展开钮等玻璃药丸文字专用，
    /// 与 textSecondary 色值不同、不可代用（C-A6 前
    /// 提；线 4 C2 同面令牌缺口，设置族随批 E 收编）。
    static var glassLabel: Color { dyn(0x48494F, 0xD1D1D6) }
    /// 玻璃标签强调色（Web --glass-label-accent
    /// #005BBB/#72B7FF，tokens.css:54/251）：标签
    /// chip 文字专用（.glass-tag 口径）——与系统
    /// accent 蓝、glassLabel 均不同值，不可代用
    /// （B2 登记项，与 glassLabel 同属标签令牌族）。
    static var glassLabelAccent: Color {
        dyn(0x005BBB, 0x72B7FF)
    }
    static var accent: Color { dyn(0x007AFF, 0x007AFF) }
    /// 跨块选区高亮（Web ::highlight(mn-xsel) 同值
    /// rgba(0,105,217,0.30)，明暗同值）：F-09 一期
    /// 行面着色专用（MomentXSelBridge 覆盖判定）。
    static var xselHighlight: Color {
        dynA(0x0069D9, 0.30, 0x0069D9, 0.30)
    }
    /// 跨块选区高亮 UIColor 变体（与 xselHighlight
    /// 同值，明暗同值故无 trait 闭包）：F-09 二期
    /// 段内分段着色（BlockTextView 属性层）专用。
    static var xselHighlightUI: UIColor {
        UIColor(rgb: 0x0069D9).withAlphaComponent(0.30)
    }
    static var warning: Color { dyn(0xFF9500, 0xFF9500) }
    static var danger: Color { dyn(0xE0433A, 0xE0433A) }
    /// 成功色（Web --color-success #34C759，tokens.css:81
    /// 单点定义、明暗同值）：备份 toast 成功图标专用——
    /// 此前误用 accent 蓝（审计二轮 S4）。
    static var success: Color { dyn(0x34C759, 0x34C759) }
    static var glassTint: Color {
        dynA(0xFFFFFF, 0.74, 0x202024, 0.86)
    }
    static var glassControlTint: Color {
        dynA(0xFFFFFF, 0.90, 0x38383C, 0.96)
    }
    static var glassBorder: Color {
        dynA(0x000000, 0.16, 0xFFFFFF, 0.16)
    }
    /// 浮层档底（Web --glass-overlay-bg：实白/深 #1C1C1E；
    /// 菜单/导出/斜杠/卡菜单四浮层专用，与内容档分开）。
    static var overlayBg: Color { dyn(0xFFFFFF, 0x1C1C1E) }
    /// 色点未选边（Web --color-black-12）。
    static var dotBorder: Color {
        dynA(0x000000, 0.12, 0xFFFFFF, 0.14)
    }
    /// 亮危险色（Web --color-danger-bright #FF3B30）。
    static var dangerBright: Color { dyn(0xFF3B30, 0xFF453A) }
    /// 浅危险色（Web --color-danger-light #FF6B6B，
    /// tokens.css:79 明暗同值）：徽章面板 ERROR 标
    /// 题专用，与 dangerBright 分工（J2-F29）。
    static var dangerLight: Color { dyn(0xFF6B6B, 0xFF6B6B) }
    /// 紫（Web --color-purple #AF52DE，tokens.css:82
    /// 明暗同值）：菜单背景行 palette 图标专用
    /// （J2-F08）。
    static var purple: Color { dyn(0xAF52DE, 0xAF52DE) }
    /// 强占位色（Web --color-placeholder-strong
    /// #C0C0C6，tokens.css:84 明暗同值）：导出行
    /// chevron 专用（J2-F13）。
    static var placeholderStrong: Color {
        dyn(0xC0C0C6, 0xC0C0C6)
    }
    /// 内容卡底（Web --card-bg #FFFFFF/#1C1C1E，
    /// tokens.css:11/218）：MD 表格外框底专用
    /// （J2-M04），与浮层玻璃底分开。
    static var cardBg: Color { dyn(0xFFFFFF, 0x1C1C1E) }
    /// 浮层档边（Web --glass-overlay-border）。
    static var overlayBorder: Color {
        dynA(0x000000, 0.18, 0xFFFFFF, 0.20)
    }
    static var quoteBg: Color {
        dynA(0x000000, 0.025, 0xFFFFFF, 0.045)
    }
    /// 代码块底（Web --code-bg 实色 #F4F4F5/#2C2C2E，
    /// 线 1 #24——原中性淡染在备忘底色上分叉）。
    static var codeBg: Color { dyn(0xF4F4F5, 0x2C2C2E) }
    /// 待办未选圈边（Web --md-checkbox-border：
    /// 浅 #73737A / 深 #B5B5BB，tokens.css:28/227）。
    /// 此前深值误抄浅值——深色下圈边恒中灰、在深
    /// 底上几乎不可见（fix_dark_mode_full 定案）。
    static var checkBorder: Color { dyn(0x73737A, 0xB5B5BB) }
    /// 填充强调面上的标签色（Web 钮面白字口径）：
    /// accent/danger/warning 实色胶囊钮的文字专用，
    /// 明暗同值。此前各使用点散写 .white 字面
    /// （fix_dark_mode_full 归令）。
    static var onAccent: Color { dyn(0xFFFFFF, 0xFFFFFF) }
    /// 诊断终端卡字色（绿 #7CFC9A，明暗同值）：终
    /// 端审美为固定调色，与 termBg 成对（此前两
    /// Diag 页各散写字面，归令）。
    static var termText: Color { dyn(0x7CFC9A, 0x7CFC9A) }
    /// 诊断终端卡底（#111，明暗同值）。
    static var termBg: Color { dyn(0x111111, 0x111111) }
    /// 按下态背景（Web :active/--fill-hover 口径）。
    static var pressBg: Color {
        dynA(0x000000, 0.05, 0xFFFFFF, 0.09)
    }
    /// 内容卡底（Web --glass-content-bg：实色白/深灰，
    /// 编辑器内卡片专用，与浮层玻璃的半透底分开）。
    static var contentBg: Color { dyn(0xFFFFFF, 0x202024) }
    /// 骨架/封面占位底（Web --border-color）。
    static var borderSoft: Color {
        dynA(0x000000, 0.05, 0xFFFFFF, 0.10)
    }
    /// 强悬停填充（Web --fill-hover-strong：中灰 10%）。
    static var fillHoverStrong: Color {
        dynA(0x7F7F7F, 0.10, 0x7F7F7F, 0.10)
    }
    /// 悬停填充（Web --fill-hover：快捷键/kbd 胶囊底）。
    static var fillHover: Color {
        dynA(0x7F7F7F, 0.06, 0x7F7F7F, 0.06)
    }
    /// 微填充（Web --fill-subtle：图文行图区/空瓦底）。
    static var fillSubtle: Color {
        dynA(0x000000, 0.03, 0xFFFFFF, 0.04)
    }
    /// 微填充 2（Web --fill-subtle-2：空瓦右格底）。
    static var fillSubtle2: Color {
        dynA(0x000000, 0.02, 0xFFFFFF, 0.03)
    }
    static var quoteBar: Color {
        dynA(0x005BBB, 0.62, 0x72B7FF, 0.72)
    }
    static var quoteText: Color { dyn(0x626267, 0xB4B4B9) }
    static var iconMuted: Color { dyn(0x8A9BB0, 0xE5E7EB) }

    /// 备忘专属底色（Web bgColor 口径）：浅色原色、深色
    /// 压暗；无色回根背景。UIColor 本体单源于 memoBgUI
    /// （压暗比只此一处，防两处漂移）。
    static func memoBg(_ hex: String?) -> Color {
        Color(uiColor: memoBgUI(hex))
    }

    /// 备忘专属底色 UIColor 变体（与 memoBg 同值）：
    /// 浅色原色、深色 ×0.55 压暗的本体实现，memoBg
    /// 为其 Color 包装。
    static func memoBgUI(_ hex: String?) -> UIColor {
        guard let hex, let rgb = rgbOf(hex) else {
            return bgUI
        }
        return UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(
                    red: rgb.0 * 0.55, green: rgb.1 * 0.55,
                    blue: rgb.2 * 0.55, alpha: 1)
            }
            return UIColor(red: rgb.0, green: rgb.1,
                           blue: rgb.2, alpha: 1)
        }
    }

    static func rgbOf(_ hex: String)
        -> (CGFloat, CGFloat, CGFloat)? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16)
        else { return nil }
        return (CGFloat((v >> 16) & 0xFF) / 255,
                CGFloat((v >> 8) & 0xFF) / 255,
                CGFloat(v & 0xFF) / 255)
    }

    static func colorOf(_ hex: String) -> Color {
        guard let rgb = rgbOf(hex) else { return .clear }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// Callout 五变体（Web editor.css .callout-* 口径）。
    static func calloutBg(_ v: String) -> Color {
        switch v {
        case "tip": return dyn(0xEAF7EE, 0x14301C)
        case "warning": return dyn(0xFFF4E0, 0x3A2A10)
        case "important": return dyn(0xF1EAFB, 0x2A1E44)
        case "caution": return dyn(0xFDECEA, 0x3D1713)
        default: return dyn(0xEAF2FE, 0x12283F)
        }
    }
    /// Callout 图标色（Web --md-callout-*-icon 令牌，
    /// tokens.css:37-41 浅色五值 / 236-240 深色五值；
    /// J2-M06 逐值对齐，此前为系统色近似）。
    static func calloutAccent(_ v: String) -> Color {
        switch v {
        case "tip": return dyn(0x1C7A34, 0x75E29A)
        case "warning": return dyn(0xAD5F00, 0xFFBD66)
        case "important": return dyn(0x8436AA, 0xD39BED)
        case "caution": return dyn(0xB3261E, 0xFF8178)
        default: return dyn(0x005BBB, 0x72B7FF)
        }
    }
    /// 正文色 UIColor 变体（与 textMain 同值）：
    /// MD 文本组承载 UITextView 的默认字色（属
    /// 性串未显式给色的 run 取视图 textColor）。
    static var textMainUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0xFFFFFF : 0x1A1A1A)
        }
    }
    static var quoteTextUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0xB4B4B9 : 0x626267)
        }
    }
    static var checkChecked: Color { dyn(0x0066CC, 0x0A84FF) }
    static var linkBlue: Color { dyn(0x005BBB, 0x72B7FF) }
    /// 链接色 UIColor 变体（与 linkBlue 同值）：MD
    /// 属性串 _link 段前景专用（J2-M01，Web
    /// --md-link-color）。
    static var linkBlueUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0x72B7FF : 0x005BBB)
        }
    }
    /// 悬停填充 UIColor 变体（与 fillHover 同值）：
    /// MD 删除线段底专用（J2-M03，Web .moment-
    /// strikethrough 的 --fill-hover 底）。
    static var fillHoverUI: UIColor {
        UIColor(rgb: 0x7F7F7F).withAlphaComponent(0.06)
    }
    /// 公式失败原码色（Web .math-source #CC0000，
    /// editor.css:330 明暗同值）：行内/块级失败态共
    /// 用。此前误用 T.danger #E0433A（二轮 E6 附带）。
    static var mathFail: Color { dyn(0xCC0000, 0xCC0000) }
    static var mathFailUI: UIColor { UIColor(rgb: 0xCC0000) }
    /// 高亮底（Web --fill-highlight rgba(255,204,0,
    /// 0.25)，tokens.css:105）：MD 渲染侧 mark 底，
    /// 与编辑面 applyHighlightTint 同值同源。
    static var fillHighlight: Color {
        dynA(0xFFCC00, 0.25, 0xFFCC00, 0.25)
    }
    static var fillHighlightUI: UIColor {
        UIColor(red: 1.0, green: 0.8, blue: 0, alpha: 0.25)
    }
    /// 斜杠命中段底（Web --fill-accent-18 rgba(0,122,
    /// 255,0.18)，tokens.css:97）：.slash-match 专用。
    static var fillAccent18: Color {
        dynA(0x007AFF, 0.18, 0x007AFF, 0.18)
    }
    static var fillAccent18UI: UIColor {
        UIColor(red: 0, green: 122.0 / 255, blue: 1,
                alpha: 0.18)
    }
    /// 待办完成态文字色 UIColor 变体（Web
    /// --md-text-muted：浅 #626267 / 深 #B4B4B9，
    /// tokens.css:25/224）：编辑面 applyDoneStyle
    /// 专用。此前使用点内联 trait 闭包散写同值，
    /// 归令单源（fix_dark_mode_full）。
    static var doneTextUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0xB4B4B9 : 0x626267)
        }
    }
    /// 代码块底 UIColor 变体（与 codeBg 同值）：
    /// 行内代码底专用（Marks.attributed 的 code
    /// run）。此前 Marks 内自持一份 trait 闭包散
    /// 写同值，归令单源（fix_dark_mode_full）。
    static var codeBgUI: UIColor {
        UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark
                ? 0x2C2C2E : 0xF4F4F5)
        }
    }
    static func dynA(_ light: UInt32, _ la: Double,
                     _ dark: UInt32, _ da: Double) -> Color {
        Color(UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(da)
                : UIColor(rgb: light).withAlphaComponent(la)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// 玻璃面（Web --glass-content 口径：材质模糊 + 染色 +
/// 0.5px 边；无投影，与原版一致）。
/// 圆角派生机制（0.9.52 卡片圆角根治，定案
/// docs/reports/fix_card_radius.md）：全仓「面」半径
/// 的唯一入口——值与 Web tokens.css --radius-* 逐值
/// 同源；嵌套内面半径只许经 concentric 由外半径与
/// 内边距派生，渲染点不再各自写死第二个数。旧况：
/// 拾起面 liftFaceRadius 自维护第二张表且已漂移
/// （图文/混排卡真面 22 而拾起框按 32、附件常态面
/// 32 而框按 22、音乐丸态真面胶囊而框按 32），拾起
/// 框与面不同心即用户点名的圆角不配。微装饰半径
/// （≤6 的骨架条/键盘键/竖条等单元素、非嵌套面）
/// 不入此表，逐项评估账见报告。
/// 贴边面政策（plan_dynamic_radius.md §3.3）：本
/// App 无自绘贴边面；将来自绘贴边面用 displayFlush
/// 定值令牌 + concentric 派生，机型表不采纳、
/// 屏角读取 SPI 永久排除。
enum Radius {
    /// --radius-22：图文卡/混排卡/gallery 网格与瓦/
    /// 图片面/视频面、附件文件行宽屏态。
    static let cardS: CGFloat = 22
    /// --radius-32：内容卡（链接卡与音乐 ready/error
    /// 态、附件图片与文件行常态、首页行卡）与玻璃卡
    /// 默认。
    static let cardL: CGFloat = 32
    /// --radius-26：首页网格方卡。
    static let grid: CGFloat = 26
    /// --radius-10：引用块面。
    static let quote: CGFloat = 10
    /// --radius-10：MD 图片裁切（.markdown-render img）。
    static let mdImage: CGFloat = 10
    /// --radius-12：callout/代码块/表格卡面与浮层卡
    /// 默认。
    static let block: CGFloat = 12
    /// --radius-999：胶囊面（音乐输入丸/链接输入丸）。
    static let pill: CGFloat = 999
    /// --radius-33：编辑页标题胶囊。
    static let titleCapsule: CGFloat = 33
    /// 拾起玻璃框外扩量（Web LIFT_INSET）。
    static let liftInset: CGFloat = 4
    /// --radius-28：面板卡（设置族/Diag/桥设置/
    /// 救援各卡、备份行卡、吐司、背景色底表）。
    static let panel: CGFloat = 28
    /// --radius-30：备份 hero 卡及其内幅面。
    static let panelHero: CGFloat = 30
    /// --radius-20：小面板（Diag 面板、救援小卡、
    /// 紧凑标题胶囊、设置小卡、开屏图标）。
    static let panelS: CGFloat = 20
    /// --radius-14：小方钮（glassControl 方钮面）。
    static let controlS: CGFloat = 14

    /// 同心派生：内面半径 = 外半径 − 内边距，钳 0。
    /// inset 为 0（出血贴边）时内面即外半径、由外层
    /// 裁切成形，不另给第二个数。
    static func concentric(outer: CGFloat,
                           inset: CGFloat) -> CGFloat {
        max(outer - inset, 0)
    }

    /// 拾起框半径：面外扩 liftInset 的同心逆运算
    /// （玻璃框 = 视觉面 ⊕ LIFT_INSET 等距外扩）。
    static func lift(face: CGFloat) -> CGFloat {
        concentric(outer: face, inset: -liftInset)
    }

    /// 附件文件行面半径（Web .attachment-file）：
    /// 常态 --radius-32；宽屏 spread 段（editor.css
    /// :726，媒体条件 (min-width:768 且 min-height:
    /// 600) 或 min-width:1100）--radius-22。宽屏判
    /// 据由 EditorView.syncWide 按同一媒体式单点喂
    /// 入（columnsActive），行面（AttachmentRow）
    /// 与拾起面（CardFace 文件行面型经 cardLift
    /// Radius 同令牌绑至此派生）共用、两面恒同
    /// 值。附件图片面不吃宽屏变值（Web
    /// 宽屏段对 .atomic.attachment 只有 break-
    /// inside），恒 cardL、不经此派生。
    static func attachmentFile(wide: Bool) -> CGFloat {
        wide ? cardS : cardL
    }
}

extension View {
    /// 宽屏收窄钳（720 居中单点）：总宽钳 720 后以
    /// 无限宽框居中；可用宽小于 720 时两框均不生效、
    /// 呈现零变化。设置族内容框与日志视窗页终端卡
    /// 共用此钳——720 字面主文件只此一处（救援页
    /// E-2 手抄一份为既定留置，R19-14 单独锁）。
    func wideNarrowClamp() -> some View {
        self
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }

    /// 设置族内容框（E-1 宽屏收窄，用户 2026-11-27
    /// 裁定）：横 20 / 顶 81 / 底 40 为设置六页共用
    /// 约定（原逐页手抄三行），宽屏总宽钳 720 居中；
    /// 窄屏时 720 框不生效、与原手抄逐值等价零变化。
    /// 诊断页 0.9.63 起同入收敛面（AUD-C-02，用户
    /// 2026-11-28 裁定）：DiagView 手抄三行改调本框。
    /// 顶距改判（用户 2026-11-28 裁定）：以用户设置
    /// 页上滑 ≈45pt 截图中的内容位置为标准，顶距由
    /// 126 改 81（= 126 − 45，截图三处偏移量测复核
    /// 见 fix_frame_top_inset_81.md）；图片页 L-4 呈
    /// 现顶让 126 自持、不随本框（自分叉登记同上）。
    func settingsContentFrame() -> some View {
        self
            .padding(.horizontal, 20)
            .padding(.top, 81)
            .padding(.bottom, 40)
            .wideNarrowClamp()
    }
}

struct GlassCard: ViewModifier {
    var radius: CGFloat = Radius.cardL
    var control: Bool = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(control ? T.glassControlTint
                                  : T.glassTint)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.glassBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// 「完成」打勾（矢量勾线，用户 2026-11-27 规
/// 格）：编辑页完成胶囊下段的勾形——不用文字、
/// 不用字符/SF 字形，纯 Path 三点折线（起笔左
/// 中、谷点左下、收笔右上，短长臂比约 1:2.2）；
/// 描边由使用点以 StrokeStyle 给（线宽 2.8、圆
/// 头圆角，与页眉 SF 图标 semibold 22 的描边量
/// 级对齐、光学大小同为 22 框）。坐标按设计框
/// 取相对值，frame 缩放即等比。
struct CheckmarkGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.27,
                           y: rect.minY + h * 0.54))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.43,
                              y: rect.minY + h * 0.70))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.75,
                              y: rect.minY + h * 0.30))
        return p
    }
}

/// 复合卡子面按位取角（内角规矩，用户 2026-11-27
/// 裁定，fix_lift_spacing.md）：由子面拼合的卡只有
/// 外轮廓四角取卡半径、内部交界角一律直角——子面
/// 按其在卡内的位置显式取角（贴顶只圆上角、贴底
/// 只圆下角、居中全直角、左右分栏同理）。不靠「无
/// 裁切即直角」的默认：图文卡占位子面在真机上底角
/// 呈圆、交界露白缺口（截图三实证），故一律显式
/// 裁切锁形。纯 Path 弧线实现，不依赖新版 SwiftUI
/// 形状类型（本工具链模块可见性有前科）。
struct CornerRect: Shape {
    var tl: CGFloat = 0
    var tr: CGFloat = 0
    var bl: CGFloat = 0
    var br: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        // 角以二次 Bézier 构造（控制点 = 角点本
        // 身）：方向约定零歧义；与真圆弧的偏差
        // ≤0.06r 且只出现在外轮廓角、恒被父级卡
        // 裁切（contentCard/glassCard/格网 clip）
        // 遮蔽，交界角半径恒 0、不涉偏差。
        let rTl = min(tl, rect.width / 2, rect.height / 2)
        let rTr = min(tr, rect.width / 2, rect.height / 2)
        let rBl = min(bl, rect.width / 2, rect.height / 2)
        let rBr = min(br, rect.width / 2, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rTl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rTr,
                               y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rTr),
            control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX,
                               y: rect.maxY - rBr))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - rBr, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + rBl,
                               y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - rBl),
            control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX,
                               y: rect.minY + rTl))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + rTl, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// 拾起框（Web .mn-lifted::before 口径，用户
/// 2026-11-26 点名补齐）：块被拾起时其视觉面四边等
/// 距外扩 LIFT_INSET 4、框半径 = 面半径 + 4（同心嵌
/// 套、随面动态适配），材质 = glass-content（与
/// GlassCard 同令牌）、无投影。挂视觉面的 background
/// 层，随行缩放同步变换（渲染外扩 ≈ 4×scale，与 Web
/// 逆映射精确 ⊕4 差 <0.2pt，不可感知）。面半径由
/// 调用方按块型给出（文本系面即行盒、图面 22、卡面
/// 32 等），解析口径对 Web resolveLiftSurface。
struct LiftFrame: View {
    var faceRadius: CGFloat
    var body: some View {
        Color.clear
            .glassCard(radius: Radius.lift(face: faceRadius))
            .padding(-Radius.liftInset)
    }
}

/// 内容卡面（Web .link-card-block 等编辑器内卡片口径）：
/// 实色 content 底 + 0.5 边 + 圆角裁切（不用浮层玻璃
/// 的材质半透底——那是菜单/底表的面）。
struct ContentCard: ViewModifier {
    var radius: CGFloat = Radius.cardL
    func body(content: Content) -> some View {
        content
            .background(T.contentBg)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.glassBorder, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// 浮层面（Web --glass-overlay 口径）：实色底 + 0.5 边
/// + 圆角裁切。菜单/导出/斜杠/卡菜单专用；Web 的
/// --glass-overlay-shadow 变量从未定义、实际无阴影，
/// 故此处同样无阴影。
struct OverlayCard: ViewModifier {
    var radius: CGFloat = Radius.cardS
    func body(content: Content) -> some View {
        content
            .background(T.overlayBg)
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(T.overlayBorder,
                                  lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    func overlayCard(radius: CGFloat = Radius.cardS) -> some View {
        modifier(OverlayCard(radius: radius))
    }
    func contentCard(radius: CGFloat = Radius.cardL) -> some View {
        modifier(ContentCard(radius: radius))
    }
    func glassCard(radius: CGFloat = Radius.cardL) -> some View {
        modifier(GlassCard(radius: radius))
    }
    func glassControl(radius: CGFloat) -> some View {
        modifier(GlassCard(radius: radius, control: true))
    }
}

/// 按下态体系（M25，Web :active 口径）：行/菜单项给背景
/// 按下态，胶囊/卡片类给 0.975 缩放，过渡 0.15s。
struct RowPressStyle: ButtonStyle {
    var radius: CGFloat = 12
    func makeBody(
        configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(configuration.isPressed
                          ? T.pressBg : Color.clear))
            .animation(.easeOut(duration: 0.15),
                       value: configuration.isPressed)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(
        configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed
                         ? 0.975 : 1)
            .animation(.easeOut(duration: 0.15),
                       value: configuration.isPressed)
    }
}

// ── 首页派生（封面/摘要/相对时间/标签，口径同 Web list） ──
extension MemoItem {
    func coverFileId(names: [String: String],
                     types: [String: String])
        -> String? { cover(names: names, types: types).0 }
    func coverURL(names: [String: String],
                  types: [String: String])
        -> String? { cover(names: names, types: types).1 }
    /// 封面（fileId, url）一次探针取齐：卡片同帧
    /// 需要两者时走此口，避免 coverFileId/coverURL
    /// 各跑一趟全树递归探针。
    func coverPair(names: [String: String],
                   types: [String: String])
        -> (String?, String?) {
        cover(names: names, types: types)
    }

    /// 判图（Web att_file_is_image_raw 单一口径）：
    /// 清单 type 非空时以其为准（trim+小写后 image/
    /// 开头即图、非图直接否决，不再看名）；type 缺
    /// 失/空才回落按名判图。type 表经 FFI attach-
    /// mentTypesJson 拉取（J1 契约扩展后补齐，此前
    /// 只出名不出 type 的暂缺已销）。
    static func attIsImage(name: String,
                           type: String?) -> Bool {
        if let t = type?.trimmingCharacters(
            in: .whitespaces), !t.isEmpty {
            return t.lowercased().hasPrefix("image/")
        }
        return attNameIsImage(name)
    }

    /// 按名判图（Web att_file_is_image_raw 的名扩
    /// 展路径）：扩展名取最后一个点后段（无点取全
    /// 名），集合 = png/jpg/jpeg/gif/webp/bmp/
    /// svg/avif/heic/heif。
    static func attNameIsImage(_ name: String) -> Bool {
        let ext: String
        if let dot = name.lastIndex(of: ".") {
            ext = String(name[name.index(after: dot)...])
                .lowercased()
        } else {
            ext = name.lowercased()
        }
        return ["png", "jpg", "jpeg", "gif", "webp",
                "bmp", "svg", "avif", "heic", "heif"]
            .contains(ext)
    }

    /// 封面 URL 白名单（Web safe_image_url /
    /// core inline_html 同规则，AUD-A-01 对齐）：
    /// trim 后 http(s) 直过；data:image/(png|
    /// jpeg|gif|webp|bmp|avif);base64 且载荷非
    /// 空、全为 base64 字符集才过；其余（空串、
    /// file:、非法 data: 等）一律 nil——探针视
    /// 为无命中、继续下探下一候选，不截断。
    static func safeCoverURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let url = raw.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let lower = url.lowercased()
        if lower.hasPrefix("http://")
            || lower.hasPrefix("https://") {
            return url
        }
        guard lower.hasPrefix("data:image/")
        else { return nil }
        let rest = lower.dropFirst("data:image/".count)
        guard let sep = rest.range(of: ";base64,")
        else { return nil }
        let ty = rest[..<sep.lowerBound]
        guard ["png", "jpeg", "gif", "webp", "bmp",
               "avif"].contains(ty) else { return nil }
        let b64 = rest[sep.upperBound...]
        guard !b64.isEmpty, b64.allSatisfy({
            $0.isASCII && ($0.isLetter || $0.isNumber
                || $0 == "+" || $0 == "/" || $0 == "=")
        }) else { return nil }
        return url
    }

    private func cover(names: [String: String],
                       types: [String: String])
        -> (String?, String?) {
        func probe(_ nodes: [[String: Any]])
            -> (String?, String?)? {
            for n in nodes {
                let ty = n["type"] as? String ?? ""
                let attrs = n["attrs"] as? [String: Any] ?? [:]
                // URL 口径与 Web cover_in_node 单
                // 口径对齐（AUD-A-01）：image 的
                // URL 过 safeCoverURL 白名单、不
                // 过视为无命中继续下探；imgText-
                // Card/imageTextRow 只取 fileId
                // （Web 无 URL 路，此前同支回退
                // 会派生 Web 不派生的封面）。
                switch ty {
                case "image":
                    if let f = attrs["fileId"] as? String,
                       !f.isEmpty { return (f, nil) }
                    if let u = MemoItem.safeCoverURL(
                        (attrs["url"] as? String)
                            ?? (attrs["src"] as? String)) {
                        return (nil, u)
                    }
                case "imgTextCard", "imageTextRow":
                    if let f = attrs["fileId"] as? String,
                       !f.isEmpty { return (f, nil) }
                case "gallery":
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items {
                        if let f = it["fileId"] as? String,
                           !f.isEmpty { return (f, nil) }
                        if let u = MemoItem.safeCoverURL(
                            it["url"] as? String) {
                            return (nil, u)
                        }
                    }
                case "attachment":
                    if let f = attrs["fileId"] as? String,
                       !f.isEmpty {
                        if attrs["image"] as? Bool ?? false {
                            return (f, nil)
                        }
                        // 清单判图（二轮小差 10）：
                        // 经「添加附件」选入的照片
                        // image 标志为假——名 = 清单
                        // 名优先、节点名兜底（Web
                        // cover_in_node 同序），判图
                        // 走 attIsImage（清单 MIME 优
                        // 先、名扩展兜底）才认封面。
                        let name = names[f]
                            ?? (attrs["name"] as? String)
                            ?? ""
                        if MemoItem.attIsImage(
                            name: name, type: types[f]) {
                            return (f, nil)
                        }
                    }
                default:
                    break
                }
                if let kids = n["children"] as? [[String: Any]],
                   let hit = probe(kids) {
                    return hit
                }
            }
            return nil
        }
        return probe(blocks.map { $0.node }) ?? (nil, nil)
    }

    func hasCover(names: [String: String],
                  types: [String: String]) -> Bool {
        let c = cover(names: names, types: types)
        return c.0 != nil || c.1 != nil
    }

    /// 归组日期：createdAt 优先（Web 口径），解析失败回退
    /// updatedAt——按更新时间归组会让老备忘一编辑就跳组。
    var bucketDate: Date {
        Clock.parseISO(createdAt) ?? updatedDate
    }

    /// 全部段落块各自的首个文本段（Web summarize 的
    /// 取材口径：遍历全部 paragraph、各取首个子节点
    /// 文本、trim 非空才计入）。此前只取首块——首段
    /// 为空/纯标签时摘要与标签整体丢失（线 3 审计）。
    var paraFirstTexts: [String] {
        var out: [String] = []
        for b in blocks where b.type == "paragraph" {
            let kids = b.node["children"] as? [[String: Any]]
                ?? []
            // 取材口径（Web summarize_uncached 逐
            // 字）：只看首个子节点的 text——缺失即
            // 空、该段不计；不向后找有 text 的子节
            // 点、不下钻 link 子节点（二轮小差 7
            // 取材细差，此前两点均与 Web 分叉）。
            let text = kids.first?["text"] as? String ?? ""
            let trimmed = text.trimmingCharacters(
                in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        return out
    }

    var firstParaText: String {
        paraFirstTexts.first ?? ""
    }

    /// 字符级标签扫描（Web scan_tags）：任意位置的 #词，
    /// 标签字符 = 字母数字/_/-/CJK 等 alphanumerics。
    var tags: [String] {
        var out: [String] = []
        var cur = ""
        var inTag = false
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "_-"))
        for ch in paraFirstTexts.joined(separator: " ") {
            if ch == "#" {
                if inTag, !cur.isEmpty, !out.contains(cur) {
                    out.append(cur)
                }
                cur = ""
                inTag = true
            } else if inTag {
                if ch.unicodeScalars.allSatisfy(
                    { allowed.contains($0) }) {
                    cur.append(ch)
                } else {
                    if !cur.isEmpty, !out.contains(cur) {
                        out.append(cur)
                    }
                    cur = ""
                    inTag = false
                }
            }
            if out.count >= 3 { break }
        }
        if inTag, !cur.isEmpty, !out.contains(cur),
           out.count < 3 {
            out.append(cur)
        }
        return out
    }

    /// Web summarize：全部段落首子文本空格拼接 →
    /// strip_markdown 全规则链 → strip_tag_tokens →
    /// 截断（文本卡 80 / 图文卡 60）；段落全空直接
    /// 回退文案，剥后为空回退首个标签名再回退文案。
    /// 规则链为 Web list.rs strip_markdown 的逐条
    /// 移植（二轮小差 7：此前近似实现缺围栏/公式/
    /// 脚注/wiki/上下标五类规则，MD 源段落会露出
    /// 语法原文）；替换顺序与 Web 严格一致。
    func summary(isImage: Bool) -> String {
        if paraFirstTexts.isEmpty {
            return Lang.t("list.no_more_text")
        }
        let joined = paraFirstTexts.joined(separator: " ")
        let stripped = Self.stripTagTokens(
            Self.stripMarkdown(joined))
        if stripped.isEmpty {
            return tags.first ?? Lang.t("list.no_more_text")
        }
        return String(stripped.prefix(isImage ? 60 : 80))
    }

    // ── strip_markdown 移植（Web list.rs）──
    // 匹配结果：(总长, 捕获范围——相对匹配起点的
    // 字符下标对)。
    typealias StripMatch = (len: Int, cap: (Int, Int)?)

    /// 扫描替换骨架（Web scan_replace）：最左、
    /// 非重叠；matcher 失败则原样输出当前字符。
    static func stripScan(
        _ chars: [Character],
        _ matcher: ([Character], Int) -> StripMatch?,
        _ emit: (ArraySlice<Character>?) -> String
    ) -> [Character] {
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            if let m = matcher(chars, i) {
                let slice: ArraySlice<Character>?
                if let cap = m.cap {
                    slice = chars[(i + cap.0)..<(i + cap.1)]
                } else {
                    slice = nil
                }
                out.append(contentsOf: emit(slice))
                i += max(m.len, 1)
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    static func stripEmitCap(
        _ cap: ArraySlice<Character>?) -> String {
        cap.map { String($0) } ?? ""
    }

    static func stripEmitEmpty(
        _ cap: ArraySlice<Character>?) -> String { "" }

    static func stripAt(_ c: [Character], _ i: Int)
        -> Character? {
        i >= 0 && i < c.count ? c[i] : nil
    }

    static func stripStarts(_ c: [Character], _ i: Int,
                            _ lit: String) -> Bool {
        let l = Array(lit)
        guard i >= 0, i + l.count <= c.count else {
            return false
        }
        for k in l.indices where c[i + k] != l[k] {
            return false
        }
        return true
    }

    static func stripEat(_ c: [Character], _ j: Int,
                         _ pred: (Character) -> Bool) -> Int {
        var j = j
        while j < c.count && pred(c[j]) { j += 1 }
        return j
    }

    static func stripIsASCIIAlnum(_ ch: Character) -> Bool {
        guard let v = ch.asciiValue else { return false }
        return (48...57).contains(v) || (65...90).contains(v)
            || (97...122).contains(v)
    }

    static func stripIsASCIIDigit(_ ch: Character) -> Bool {
        guard let v = ch.asciiValue else { return false }
        return (48...57).contains(v)
    }

    /// 脚注定义（仅行首）→ 整段删除。
    static func stripFootnoteDef(_ c: [Character], _ i: Int)
        -> StripMatch? {
        if i > 0 && c[i - 1] != "\n" { return nil }
        guard stripStarts(c, i, "[^") else { return nil }
        let j = stripEat(c, i + 2) { $0 != "]" }
        if j == i + 2 || !stripStarts(c, j, "]:") {
            return nil
        }
        var end = stripEat(c, j + 2) { $0 != "\n" }
        while end < c.count && c[end] == "\n",
              let next = stripAt(c, end + 1),
              next == " " || next == "\t" {
            let line = stripEat(c, end + 1) {
                $0 == " " || $0 == "\t"
            }
            end = stripEat(c, line) { $0 != "\n" }
        }
        return (end - i, nil)
    }

    /// [[甲|乙]] → 乙。
    static func stripWikiPipe(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "[[") else { return nil }
        let g1 = stripEat(c, i + 2) { $0 != "]" && $0 != "|" }
        if g1 == i + 2 || stripAt(c, g1) != "|" {
            return nil
        }
        let g2s = g1 + 1
        let g2 = stripEat(c, g2s) { $0 != "]" }
        if g2 == g2s || !stripStarts(c, g2, "]]") {
            return nil
        }
        return (g2 + 2 - i, (g2s - i, g2 - i))
    }

    /// [[甲]] → 甲。
    static func stripWiki(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "[[") else { return nil }
        let g = stripEat(c, i + 2) { $0 != "]" }
        if g == i + 2 || !stripStarts(c, g, "]]") {
            return nil
        }
        return (g + 2 - i, (2, g - i))
    }

    /// [^注] → 删除。
    static func stripFootnoteRef(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "[^") else { return nil }
        let g = stripEat(c, i + 2) { $0 != "]" }
        if g == i + 2 || stripAt(c, g) != "]" {
            return nil
        }
        return (g + 1 - i, nil)
    }

    /// $$…$$（惰性）→ 内文。
    static func stripMathBlock(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "$$") else { return nil }
        var k = i + 2
        while k < c.count {
            if stripStarts(c, k, "$$") {
                return (k + 2 - i, (2, k - i))
            }
            k += 1
        }
        return nil
    }

    /// ^(…) / ~(…) 括号形上下标 → 内文。
    static func stripParenForm(_ c: [Character], _ i: Int,
                               _ open: String, _ close: String)
        -> StripMatch? {
        guard stripStarts(c, i, open) else { return nil }
        let bs = i + 2
        let be = stripEat(c, bs) {
            $0 != "(" && $0 != ")" && $0 != "\n"
        }
        if be == bs || !stripStarts(c, be, close) {
            return nil
        }
        return (be + 2 - i, (2, be - i))
    }

    /// ^词^ 上标 → 内文（词 = 字母数字与 ,+-）。
    static func stripSup(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripAt(c, i) == "^" else { return nil }
        guard let first = stripAt(c, i + 1),
              stripIsASCIIAlnum(first) else { return nil }
        let be = stripEat(c, i + 2) {
            stripIsASCIIAlnum($0) || $0 == ","
                || $0 == "+" || $0 == "-"
        }
        if stripAt(c, be) != "^" { return nil }
        return (be + 1 - i, (1, be - i))
    }

    /// ==…== 高亮 → 内文。
    static func stripHighlight(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "==") else { return nil }
        let be = stripEat(c, i + 2) { $0 != "=" }
        if be == i + 2 || !stripStarts(c, be, "==") {
            return nil
        }
        return (be + 2 - i, (2, be - i))
    }

    /// ```…``` 围栏 → 占位词（emit 侧给值）。
    static func stripFence(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "```") else { return nil }
        var k = i + 3
        while k < c.count {
            if stripStarts(c, k, "```") {
                return (k + 3 - i, nil)
            }
            k += 1
        }
        return nil
    }

    /// `…` 行内代码 → 内文。
    static func stripCodeSpan(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripAt(c, i) == "`" else { return nil }
        let be = stripEat(c, i + 1) { $0 != "`" }
        if be == i + 1 || stripAt(c, be) != "`" {
            return nil
        }
        return (be + 1 - i, (1, be - i))
    }

    /// ![图注](址) → 图注。
    static func stripImage(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripStarts(c, i, "![") else { return nil }
        let ae = stripEat(c, i + 2) { $0 != "]" }
        if !stripStarts(c, ae, "](") { return nil }
        let ue = stripEat(c, ae + 2) { $0 != ")" }
        if ue == ae + 2 || stripAt(c, ue) != ")" {
            return nil
        }
        return (ue + 1 - i, (2, ae - i))
    }

    /// [文](址) → 文。
    static func stripLink(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard stripAt(c, i) == "[" else { return nil }
        let te = stripEat(c, i + 1) { $0 != "]" }
        if te == i + 1 || !stripStarts(c, te, "](") {
            return nil
        }
        let ue = stripEat(c, te + 2) { $0 != ")" }
        if ue == te + 2 || stripAt(c, ue) != ")" {
            return nil
        }
        return (ue + 1 - i, (1, te - i))
    }

    /// 行首锚点（串首或 \n 本身，替换时原样保留）。
    static func stripLineAnchor(_ c: [Character], _ i: Int)
        -> (alen: Int, body: Int)? {
        if i == 0 { return (0, 0) }
        if c[i] == "\n" { return (1, i + 1) }
        return nil
    }

    /// 行首 #{1,6}+空白 → 锚点。
    static func stripHeading(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard let a = stripLineAnchor(c, i) else {
            return nil
        }
        let hashes = stripEat(c, a.body) { $0 == "#" } - a.body
        if hashes == 0 || hashes > 6 { return nil }
        let after = stripEat(c, a.body + hashes) {
            $0.isWhitespace
        }
        if after == a.body + hashes { return nil }
        return (after - i, (0, a.alen))
    }

    /// 行首 >+可选一空白 → 锚点。
    static func stripQuote(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard let a = stripLineAnchor(c, i) else {
            return nil
        }
        guard stripAt(c, a.body) == ">" else { return nil }
        var end = a.body + 1
        if let ch = stripAt(c, end), ch.isWhitespace {
            end += 1
        }
        return (end - i, (0, a.alen))
    }

    /// 行首 [-*+]+空白 → 锚点。
    static func stripBullet(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard let a = stripLineAnchor(c, i) else {
            return nil
        }
        guard let ch = stripAt(c, a.body),
              ch == "-" || ch == "*" || ch == "+" else {
            return nil
        }
        let after = stripEat(c, a.body + 1) {
            $0.isWhitespace
        }
        if after == a.body + 1 { return nil }
        return (after - i, (0, a.alen))
    }

    /// 行首 数字.+空白 → 锚点。
    static func stripNumbered(_ c: [Character], _ i: Int)
        -> StripMatch? {
        guard let a = stripLineAnchor(c, i) else {
            return nil
        }
        let digits = stripEat(c, a.body) {
            stripIsASCIIDigit($0)
        } - a.body
        if digits == 0
            || stripAt(c, a.body + digits) != "." {
            return nil
        }
        let after = stripEat(c, a.body + digits + 1) {
            $0.isWhitespace
        }
        if after == a.body + digits + 1 { return nil }
        return (after - i, (0, a.alen))
    }

    /// 成对定界符（Web paired）：delim+内文+delim →
    /// 内文，内文不得含 excl 字符。
    static func stripPaired(_ s: String, _ delim: String,
                            _ excl: Character) -> String {
        let d = Array(delim)
        let out = stripScan(Array(s), { c, i in
            guard stripStarts(c, i, delim) else {
                return nil
            }
            let be = stripEat(c, i + d.count) { $0 != excl }
            if be == i + d.count
                || !stripStarts(c, be, delim) {
                return nil
            }
            return (be + d.count - i, (d.count, be - i))
        }, stripEmitCap)
        return String(out)
    }

    /// ~词~ 单波浪下标（Web strip_single_tilde_sub）：
    /// 前一字符不得为 ~，结尾 ~ 后不得紧跟 ~。
    static func stripSingleTildeSub(_ s: String) -> String {
        let chars = Array(s)
        let n = chars.count
        func bodyChar(_ ch: Character) -> Bool {
            stripIsASCIIAlnum(ch) || ch == ","
                || ch == "+" || ch == "-"
        }
        var out: [Character] = []
        var pos = 0
        while pos < n {
            let prefixLen: Int?
            if pos == 0 {
                prefixLen = 0
            } else if chars[pos] != "~" {
                prefixLen = 1
            } else {
                prefixLen = nil
            }
            var matched: (Int, Int, Int)?
            if let pl = prefixLen {
                var j = pos + pl
                if j < n && chars[j] == "~" {
                    j += 1
                    if j < n && stripIsASCIIAlnum(chars[j]) {
                        let start = j
                        while j < n && bodyChar(chars[j]) {
                            j += 1
                        }
                        if j < n && chars[j] == "~",
                           !(j + 1 < n && chars[j + 1] == "~") {
                            matched = (pl, start, j)
                        }
                    }
                }
            }
            if let (pl, start, end) = matched {
                out.append(contentsOf: chars[pos..<(pos + pl)])
                out.append(contentsOf: chars[start..<end])
                pos = end + 1
            } else {
                out.append(chars[pos])
                pos += 1
            }
        }
        return String(out)
    }

    /// Web looksLikeMathExpression。
    static func stripLooksLikeMath(_ expr: String) -> Bool {
        let v = expr.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if v.isEmpty { return false }
        let chars = Array(v)
        func isASCIILetter(_ ch: Character) -> Bool {
            guard let x = ch.asciiValue else { return false }
            return (65...90).contains(x)
                || (97...122).contains(x)
        }
        if chars.count == 1 && isASCIILetter(chars[0]) {
            return true
        }
        for (idx, ch) in chars.enumerated() {
            if ch == "\\", idx + 1 < chars.count,
               isASCIILetter(chars[idx + 1]) {
                return true
            }
            if stripIsASCIIDigit(ch) { return true }
            if "=+-*/^_{}<>".contains(ch) { return true }
            if ch.unicodeScalars.count == 1,
               let sv = ch.unicodeScalars.first?.value,
               (0x03B1...0x03C9).contains(sv)
                || (0x0391...0x03A9).contains(sv) {
                return true
            }
        }
        return false
    }

    /// $…$ 行内公式（Web strip_math_inline）：未
    /// 转义且像公式才剥 $，否则原样保留整段。
    static func stripMathInline(_ s: String) -> String {
        let chars = Array(s)
        let n = chars.count
        var out: [Character] = []
        var i = 0
        while i < n {
            if chars[i] == "$" {
                let be = stripEat(chars, i + 1) {
                    $0 != "$" && $0 != "\n"
                }
                if be > i + 1 && stripAt(chars, be) == "$" {
                    let inner = String(chars[(i + 1)..<be])
                    var backslashes = 0
                    var k = i
                    while k > 0 && chars[k - 1] == "\\" {
                        backslashes += 1
                        k -= 1
                    }
                    if backslashes % 2 == 0
                        && stripLooksLikeMath(inner) {
                        out.append(contentsOf: inner)
                    } else {
                        out.append(contentsOf: chars[i...be])
                    }
                    i = be + 1
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return String(out)
    }

    static func stripCollapseNewlines(_ s: String) -> String {
        var out: [Character] = []
        var inRun = false
        for ch in s {
            if ch == "\n" {
                if !inRun {
                    out.append(" ")
                    inRun = true
                }
            } else {
                inRun = false
                out.append(ch)
            }
        }
        return String(out)
    }

    static func stripCollapseSpaces(_ s: String) -> String {
        var out: [Character] = []
        var inRun = false
        for ch in s {
            if ch.isWhitespace {
                if !inRun {
                    out.append(" ")
                    inRun = true
                }
            } else {
                inRun = false
                out.append(ch)
            }
        }
        return String(out)
    }

    /// 规则链总装（顺序 = Web strip_markdown）。
    /// 围栏占位词：Web 为全语言硬编码的同词，原生
    /// 走语言包 slash.code_block（五语既有键；zh
    /// 与 Web 逐字一致，其余语言为本地化——Web
    /// 硬编码属未本地化形态，按行为等价更优）。
    static func stripMarkdown(_ text: String) -> String {
        func pass(
            _ s: String,
            _ m: @escaping ([Character], Int) -> StripMatch?,
            _ e: @escaping (ArraySlice<Character>?) -> String
        ) -> String {
            String(stripScan(Array(s), m, e))
        }
        var s = pass(text, stripFootnoteDef, stripEmitEmpty)
        s = pass(s, stripWikiPipe, stripEmitCap)
        s = pass(s, stripWiki, stripEmitCap)
        s = pass(s, stripFootnoteRef, stripEmitEmpty)
        s = pass(s, stripMathBlock, stripEmitCap)
        s = pass(s, { stripParenForm($0, $1, "^(", ")^") },
                 stripEmitCap)
        s = pass(s, stripSup, stripEmitCap)
        s = pass(s, { stripParenForm($0, $1, "~(", ")~") },
                 stripEmitCap)
        s = stripSingleTildeSub(s)
        s = pass(s, stripHighlight, stripEmitCap)
        let fenceText = " " + Lang.t("slash.code_block")
            + " "
        s = pass(s, stripFence) { _ in fenceText }
        s = pass(s, stripCodeSpan, stripEmitCap)
        s = pass(s, stripImage, stripEmitCap)
        s = pass(s, stripLink, stripEmitCap)
        s = pass(s, stripHeading, stripEmitCap)
        s = pass(s, stripQuote, stripEmitCap)
        s = pass(s, stripBullet, stripEmitCap)
        s = pass(s, stripNumbered, stripEmitCap)
        s = stripPaired(s, "**", "*")
        s = stripPaired(s, "__", "_")
        s = stripPaired(s, "*", "*")
        s = stripPaired(s, "_", "_")
        s = stripPaired(s, "~~", "~")
        s = stripMathInline(s)
        s = stripCollapseNewlines(s)
        s = stripCollapseSpaces(s)
        return s.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Web strip_tag_tokens：删除全部 #标签词（不
    /// 限已收集标签），标签字符口径与 tags 扫描
    /// 同集（字母数字/_/-）；仅 trim 两端、不再
    /// 折叠空格（Web 同）。
    static func stripTagTokens(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "_-"))
        let chars = Array(s)
        var out: [Character] = []
        var i = 0
        while i < chars.count {
            if chars[i] == "#" {
                var j = i + 1
                while j < chars.count,
                      chars[j].unicodeScalars.allSatisfy(
                        { allowed.contains($0) }) {
                    j += 1
                }
                if j > i + 1 {
                    i = j
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return String(out).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Web time_ago 四分支：今天→时刻（经 Fmt.timeOfDay，
    /// 12/24 时制与上午/下午词随 app 内语言）、昨天→
    /// 「昨天」（group.yesterday）、同年→M/D、跨年→Y/M/D。
    var ago: String {
        let d = updatedDate
        let cal = Calendar.current
        if cal.isDateInToday(d) {
            return Fmt.timeOfDay(d)
        }
        if cal.isDateInYesterday(d) {
            return Lang.t("group.yesterday")
        }
        let f = DateFormatter()
        f.locale = Fmt.locale
        if cal.component(.year, from: d)
            == cal.component(.year, from: Date()) {
            f.dateFormat = "M/d"
        } else {
            f.dateFormat = "yyyy/M/d"
        }
        return f.string(from: d)
    }

    /// 图文卡判定（Web has_image）：顶层含图类块或
    /// 图片附件即图文卡，再 ∪ 封面可派生（cover 递
    /// 归命中，含清单判图的附件与嵌套图块）——样式
    /// 门与封面派生同源（二轮小差 10）。
    func hasImageShape(names: [String: String],
                       types: [String: String])
        -> Bool {
        for b in blocks {
            switch b.type {
            case "image", "gallery", "imgTextCard",
                 "imageTextRow":
                return true
            case "attachment":
                let attrs = b.node["attrs"] as? [String: Any]
                if attrs?["image"] as? Bool == true {
                    return true
                }
                // 单文件形：清单名优先、节点名兜底
                // 取名，判图走 attIsImage（清单
                // MIME 优先，与 cover 探针同序）。
                if let f = attrs?["fileId"] as? String,
                   !f.isEmpty {
                    let name = names[f]
                        ?? (attrs?["name"] as? String) ?? ""
                    if MemoItem.attIsImage(
                        name: name, type: types[f]) {
                        return true
                    }
                }
                // items 形（导入文档的聚合附件）：
                // 任一项判图即命中（名 = 清单名优
                // 先、项名兜底；无 fid 项只按名判）。
                let items = attrs?["items"]
                    as? [[String: Any]] ?? []
                for it in items {
                    let fid = it["fileId"] as? String
                    let name = (fid.flatMap { names[$0] })
                        ?? (it["name"] as? String)
                        ?? (it["fileName"] as? String) ?? ""
                    if MemoItem.attIsImage(
                        name: name,
                        type: fid.flatMap { types[$0] }) {
                        return true
                    }
                }
                if !items.isEmpty,
                   let n = attrs?["name"] as? String,
                   MemoItem.attNameIsImage(n) {
                    return true
                }
            default:
                break
            }
        }
        return hasCover(names: names, types: types)
    }
}

// ── 恐龙线稿头像（与 Web icons.rs DINO_PATHS 同一份
// path 数据，viewBox 512，描边 icon-muted/22/圆头） ──
struct DinoView: View {
    var size: CGFloat

    static let paths: [String] = [
        "M 90,460 L 90,170 C 90,110 140,70 210,70 L 380,95 C 440,95 470,130 470,185 C 470,225 450,240 410,245 C 350,250 280,230 210,265 C 190,275 190,295 210,310 C 270,350 350,380 410,360 C 435,350 440,325 410,315",
        "M 160,330 C 180,380 230,440 280,460",
        "M 240,365 C 220,400 240,440 310,460",
        "M 90,460 L 310,460",
        "M 415,135 C 425,140 435,150 435,160",
        "M 230,115 C 260,95 310,120 355,140",
        "M 255,140 C 255,170 290,195 320,185 C 345,175 350,150 335,135",
        "M 290,145 C 290,165 315,165 315,150",
        "M 250,243 L 255,265 L 265,243 M 275,245 L 282,270 L 292,245 M 302,246 L 310,273 L 320,247 M 330,248 L 340,275 L 350,248 M 360,249 L 370,274 L 380,248 M 390,248 L 400,270 L 408,246 M 415,244 L 425,263 L 432,240 M 438,235 L 448,252 L 452,228",
        "M 250,323 L 255,305 L 263,326 M 273,329 L 280,308 L 288,333 M 298,336 L 306,313 L 314,340 M 324,343 L 333,318 L 341,346 M 351,348 L 361,323 L 369,351 M 379,352 L 389,328 L 396,353 M 404,351 L 413,330 L 418,348",
    ]

    /// 极简 SVG path 解析（仅 M/L/C，与 DINO_PATHS 实际
    /// 用到的命令集一致），坐标按 viewBox 512 缩放。
    static func parse(_ d: String, scale s: CGFloat) -> Path {
        var path = Path()
        let tokens = d.replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
        var i = 0
        var cmd = ""
        func num() -> CGFloat {
            defer { i += 1 }
            return (CGFloat(Double(tokens[i]) ?? 0)) * s
        }
        while i < tokens.count {
            if tokens[i].allSatisfy({ $0.isLetter }) {
                cmd = tokens[i]
                i += 1
                if cmd == "M" {
                    let x = num(), y = num()
                    path.move(to: CGPoint(x: x, y: y))
                    cmd = "L"
                }
                continue
            }
            switch cmd {
            case "L":
                let x = num(), y = num()
                path.addLine(to: CGPoint(x: x, y: y))
            case "C":
                let x1 = num(), y1 = num()
                let x2 = num(), y2 = num()
                let x = num(), y = num()
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: x1, y: y1),
                    control2: CGPoint(x: x2, y: y2))
            default:
                i += 1
            }
        }
        return path
    }

    var body: some View {
        let s = size / 512
        ZStack {
            ForEach(0..<Self.paths.count, id: \.self) { i in
                Self.parse(Self.paths[i], scale: s)
                    .stroke(T.iconMuted,
                            style: StrokeStyle(
                                lineWidth: 22 * s,
                                lineCap: .round,
                                lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 头像面：玻璃圆 + 恐龙线稿；备忘有自定义头像
/// （avatars 通道，data URL）时整圆贴图（Web 同口径）。
final class AvatarHolder: ObservableObject {
    @Published var custom: UIImage?

    func refresh(memoId: String?, library: Library?) {
        guard let id = memoId, let library else {
            custom = nil
            return
        }
        library.loadAvatar(for: id)
        if let url = library.avatarDataURL(for: id) {
            custom = AvatarView.image(fromDataURL: url)
        } else {
            custom = nil
        }
    }
}

struct AvatarView: View {
    var size: CGFloat
    var memoId: String? = nil
    var library: Library? = nil
    @StateObject private var holder = AvatarHolder()

    // 圆内恐龙构图常数（相对圆径 D，用户
    // 2026-11-28 参考图定案，fix_avatar_dino_
    // position）：恐龙描边外接框在 viewBox
    // 512 口径为 x 79…481（宽 402）/ y 59…471
    // （路径坐标 ± 描边半宽 11）；目标占 D 比
    // 例——描边宽 0.698、左距 0.191、顶距
    // 0.337、底边越圆底 0.052 由圆裁切（下巴/
    // 颈部贴圆下缘）。画布 = 0.698÷402×512 =
    // 0.8891；offsetX = 0.191 − 79×0.698÷402
    // = 0.0538；offsetY = 0.337 − 59×0.698÷
    // 402 = 0.2346。首页/编辑页共用本组件，
    // 常数单点、两处同值同源。
    static let dinoCanvasScale: CGFloat = 0.8891
    static let dinoOffsetX: CGFloat = 0.0538
    static let dinoOffsetY: CGFloat = 0.2346

    static func image(fromDataURL s: String) -> UIImage? {
        guard s.hasPrefix("data:"),
              let comma = s.firstIndex(of: ","),
              s[..<comma].contains("base64") else { return nil }
        let b64 = String(s[s.index(after: comma)...])
        guard let d = Data(base64Encoded: b64) else {
            return nil
        }
        return UIImage(data: d)
    }

    var body: some View {
        Group {
            if let custom = holder.custom {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // 回退恐龙：圆框本体（尺寸/glass/
                // 点按）零改动，只按上方构图常数
                // 摆圆内绘图。旧 Web 口径（size−8
                // 底对齐，list.rs:1599-1652）下绘
                // 图顶距仅 0.214D、底悬空 0.071D，
                // 与参考图（顶距 0.337D、底贴圆
                // 下缘裁切）分叉，本批改判；Web
                // 侧未动、分叉登记于报告。
                DinoView(size: size * Self.dinoCanvasScale)
                    .offset(x: size * Self.dinoOffsetX,
                            y: size * Self.dinoOffsetY)
                    .frame(width: size, height: size,
                           alignment: .topLeading)
                    .glassControl(radius: Radius.pill)
            }
        }
        .onAppear {
            holder.refresh(memoId: memoId, library: library)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .momentAvatarChanged)) { note in
            if (note.object as? String) == memoId {
                holder.refresh(memoId: memoId,
                               library: library)
            }
        }
    }
}

extension Notification.Name {
    static let momentAvatarChanged =
        Notification.Name("momentAvatarChanged")
}

// ── 天气（Web weather.rs 口径原生化） ──────────────
// 链：列表可见后 1.5s 触发 → 30 分钟缓存 → GPS 定位
// （5s 超时）→ ipapi IP 兜底 → 和风主链 → 彩云兜底。
// key 优先序（用户裁定）：设置页自填 > 构建注入的
// bundle weather-keys.json；和风 key 为空整链不发请求。
final class WeatherService: NSObject, ObservableObject,
    CLLocationManagerDelegate {
    static let shared = WeatherService()

    struct Now {
        var temp: Int
        var city: String
        var text: String
    }

    @Published var now: Now?
    private let manager = CLLocationManager()
    private var inFlight = false
    /// 在飞期间到达的刷新请求待接续标记：本趟
    /// 收口后由 refreshIfNeeded 的 Task 尾续跑，
    /// 请求不被 inFlight 守卫吞掉（W-T1）。
    private var refreshPending = false
    /// key 世代：key 变更失效时自增；fetch 以
    /// 入口捕获值校验落盘/置值点，旧世代（旧
    /// key）结果整趟作废（W-T1 世代守卫）。
    private var keyGeneration = 0
    private var locContinuation:
        CheckedContinuation<(Double, Double)?, Never>?
    private var locResumed = false

    /// 生效来源（设置主页与天气页共用同一派生，
    /// 避免两处各写一份判据）。
    enum KeySource: String {
        case custom
        case builtin
        case none
    }

    /// 构建注入的 bundle key 只解析一次（进程级
    /// 缓存）：key()/keySource() 每轮设置页求值都
    /// 会调用，不再重复读盘解析 JSON。
    private static let bundleKeys: [String: String] = {
        guard let url = Bundle.main.url(
            forResource: "weather-keys", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(
                with: data)) as? [String: String] else {
            return [:]
        }
        return obj
    }()

    static func customKey(_ name: String) -> String {
        UserDefaults.standard
            .string(forKey: "weatherKey_" + name) ?? ""
    }

    static func keySource(_ name: String) -> KeySource {
        if !customKey(name).isEmpty { return .custom }
        if !(bundleKeys[name] ?? "").isEmpty {
            return .builtin
        }
        return .none
    }

    static func key(_ name: String) -> String {
        switch keySource(name) {
        case .custom:
            return customKey(name)
        case .builtin:
            return bundleKeys[name] ?? ""
        case .none:
            return ""
        }
    }

    private func readCache() -> (Now, Double)? {
        guard let raw = UserDefaults.standard
            .string(forKey: "weatherCacheV1"),
              let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(
                with: data)) as? [String: Any],
              let temp = obj["temp"] as? Int,
              let ts = obj["ts"] as? Double else {
            return nil
        }
        return (Now(temp: temp,
                    city: obj["city"] as? String ?? "",
                    text: obj["text"] as? String ?? ""), ts)
    }

    private func writeCache(_ w: Now) {
        let obj: [String: Any] = [
            "temp": w.temp, "city": w.city, "text": w.text,
            "ts": Date().timeIntervalSince1970,
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: obj),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s,
                forKey: "weatherCacheV1")
        }
    }

    /// key 变更失效单点（W-T1，设计 impl_weather_
    /// tail §3）：编辑器 commit/clear 真变更后的
    /// 唯一入口，四件收敛一处——世代自增（在飞旧
    /// 请求结果整趟作废）、清呈现（now=nil 回落
    /// 缺数形态，防新 key 拉取失败时旧数永驻）、
    /// 删缓存（删除权收归服务，与 readCache/
    /// writeCache 同置一类）、主动重拉（不依赖
    /// ListView onAppear 重入）。此刷新是用户在
    /// 设置页的显式编辑后果、非自动刷新，不进
    /// OPS 的 weatherRefresh guard（与手动刷新
    /// 同类，W-T10 交叉口径）；Diag 行使其在指
    /// 令禁用期亦可审计。
    func invalidateAfterKeyChange() {
        keyGeneration += 1
        now = nil
        UserDefaults.standard.removeObject(
            forKey: "weatherCacheV1")
        DiagLog.shared.log(.info,
            "WEATHER invalidate src=keychange")
        refreshIfNeeded()
    }

    func refreshIfNeeded() {
        if let (w, ts) = readCache(),
           Date().timeIntervalSince1970 - ts < 1800 {
            now = w
            return
        }
        guard !inFlight else {
            refreshPending = true
            return
        }
        inFlight = true
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 1_500_000_000)
            await self.fetch()
            self.inFlight = false
            if self.refreshPending {
                self.refreshPending = false
                self.refreshIfNeeded()
            }
        }
    }

    private func fetch() async {
        // 世代守卫（W-T1）：入口捕获当前世代，
        // 全趟落盘/置值点以此校验；key 中途变更
        // 则本趟（旧 key）结果整趟作废，由失效侧
        // 已发的刷新经 refreshPending 接续。
        let gen = keyGeneration
        var ipCity = ""
        var coords = await gpsCoords()
        if coords == nil {
            if let ip = await fetchJSON(
                "https://ipapi.co/json/") {
                if let c = ip["city"] as? String {
                    let region = ip["region"] as? String ?? ""
                    // IP 兜底城名过英转中表（Web
                    // to_cn 同口径，批 K F11）：在
                    // 生产点单点转换、和风/彩云两条
                    // 消费链同享（Web 在渲染侧整串
                    // 查表——复合「City Region」串
                    // 整串未命中回原文、裸城名命中
                    // 转中文，两端逐值一致）。
                    ipCity = Self.cityToCn(
                        region.isEmpty ? c
                            : "\(c) \(region)")
                }
                if let la = ip["latitude"] as? Double,
                   let lo = ip["longitude"] as? Double {
                    coords = (la, lo)
                }
            }
        }
        guard let (lat, lng) = coords else {
            DiagLog.shared.log(.info,
                "WEATHER locate failed (gps + ip)")
            return
        }
        let qwKey = Self.key("qweather")
        if qwKey.isEmpty {
            DiagLog.shared.log(.warn,
                "WEATHER no api key, skip")
            return
        }
        if let w = await fetchQWeather(
            lat: lat, lng: lng, key: qwKey,
            ipCity: ipCity, gen: gen) {
            await MainActor.run {
                if gen == self.keyGeneration {
                    self.now = w
                }
            }
            return
        }
        if let w = await fetchCaiyun(
            lat: lat, lng: lng, ipCity: ipCity,
            gen: gen) {
            await MainActor.run {
                if gen == self.keyGeneration {
                    self.now = w
                }
            }
            return
        }
        DiagLog.shared.log(.info,
            "WEATHER provider=fail (qweather + caiyun)")
    }

    private func fetchJSON(_ urlStr: String) async
        -> [String: Any]? {
        guard let url = URL(string: urlStr) else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared
            .data(for: req) else { return nil }
        return (try? JSONSerialization.jsonObject(
            with: data)) as? [String: Any]
    }

    private func fetchQWeather(lat: Double, lng: Double,
                               key: String, ipCity: String,
                               gen: Int)
        async -> Now? {
        let nowURL = "https://jq3dna235e.re.qweatherapi.com"
            + "/v7/weather/now?location=\(lng),\(lat)"
            + "&key=\(key)"
        guard let qw = await fetchJSON(nowURL),
              (qw["code"] as? String) == "200",
              let n = qw["now"] as? [String: Any],
              let text = n["text"] as? String else {
            DiagLog.shared.log(.info,
                "WEATHER qweather now failed")
            return nil
        }
        let temp: Int?
        if let s = n["temp"] as? String {
            temp = Int(s)
        } else if let v = n["temp"] as? Int {
            temp = v
        } else { temp = nil }
        guard let temp else { return nil }
        var city = await geocoderCity(lat: lat, lng: lng)
            ?? ""
        if city.isEmpty {
            let geoURL = "https://jq3dna235e.re"
                + ".qweatherapi.com/geo/v2/city/lookup"
                + "?location=\(lng),\(lat)&key=\(key)"
            if let geo = await fetchJSON(geoURL),
               (geo["code"] as? String) == "200",
               let loc = (geo["location"]
                as? [[String: Any]])?.first {
                let name = loc["name"] as? String ?? ""
                let adm2 = loc["adm2"] as? String ?? ""
                city = adm2.isEmpty ? name : adm2 + name
            }
        }
        if city.isEmpty { city = ipCity }
        let w = Now(temp: temp, city: city, text: text)
        // 世代守卫（W-T1）：落盘与 fetched 打点同
        // 在主线程与 invalidate 的世代自增/删缓存
        // 串行化——旧世代结果不回写缓存、不冒充
        // 新数打点（校验不过整趟作废）。
        await MainActor.run {
            guard gen == self.keyGeneration else {
                return
            }
            self.writeCache(w)
            DiagLog.shared.log(.info,
                "WEATHER fetched provider=qweather "
                + "\(temp)° \(city) \(text)")
        }
        return w
    }

    private func geocoderCity(lat: Double, lng: Double)
        async -> String? {
        let geo = CLGeocoder()
        let loc = CLLocation(latitude: lat, longitude: lng)
        let places = try? await geo.reverseGeocodeLocation(
            loc, preferredLocale: Locale(
                identifier: "zh_CN"))
        guard let p = places?.first else { return nil }
        let city = p.locality ?? p.administrativeArea ?? ""
        return city.isEmpty ? nil : city
    }

    private func fetchCaiyun(lat: Double, lng: Double,
                             ipCity: String, gen: Int)
        async -> Now? {
        let key = Self.key("caiyun")
        if key.isEmpty {
            DiagLog.shared.log(.info,
                "WEATHER caiyun skipped (no key)")
            return nil
        }
        let urlStr = "https://api.caiyunapp.com/v2.6/"
            + "\(key)/\(lng),\(lat)/weather.jsonp"
            + "?callback=MYCALLBACK"
        guard let url = URL(string: urlStr) else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared
            .data(for: req),
              var raw = String(data: data, encoding: .utf8)
        else {
            DiagLog.shared.log(.info,
                "WEATHER caiyun fallback failed")
            return nil
        }
        if raw.hasPrefix("MYCALLBACK(") {
            raw = String(raw.dropFirst("MYCALLBACK(".count))
        }
        if raw.hasSuffix(")") {
            raw = String(raw.dropLast())
        }
        guard let jdata = raw.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(
                with: jdata)) as? [String: Any],
              (j["status"] as? String) == "ok",
              let rt = (j["result"] as? [String: Any])?[
                "realtime"] as? [String: Any],
              let t = rt["temperature"] as? Double else {
            DiagLog.shared.log(.info,
                "WEATHER caiyun fallback failed")
            return nil
        }
        let temp = Int((t + 0.5).rounded(.down))
        let skycon = rt["skycon"] as? String ?? ""
        let w = Now(temp: temp, city: ipCity,
                    text: Self.caiyunCondition(skycon))
        // 世代守卫（W-T1）：同 fetchQWeather 落盘
        // 点口径——主线程串行校验，旧世代整趟作废。
        await MainActor.run {
            guard gen == self.keyGeneration else {
                return
            }
            self.writeCache(w)
            DiagLog.shared.log(.info,
                "WEATHER fetched provider=caiyun-fallback "
                + "\(temp)° \(ipCity) \(w.text)")
        }
        return w
    }

    /// 城市英转中（Web weather.rs to_cn 逐值移植，
    /// 原版 CN_CITY 表）：整串精确命中回中文、未
    /// 命中回原文（批 K F11）。
    static func cityToCn(_ name: String) -> String {
        switch name {
        case "Beijing": return "北京"
        case "Shanghai": return "上海"
        case "Guangzhou": return "广州"
        case "Shenzhen": return "深圳"
        case "Hangzhou": return "杭州"
        case "Nanjing": return "南京"
        case "Chengdu": return "成都"
        case "Wuhan": return "武汉"
        case "Tianjin": return "天津"
        case "Chongqing": return "重庆"
        case "Shenyang": return "沈阳"
        case "Changchun": return "长春"
        case "Harbin": return "哈尔滨"
        case "Dalian": return "大连"
        case "Qingdao": return "青岛"
        case "Jinan": return "济南"
        case "Zhengzhou": return "郑州"
        case "Changsha": return "长沙"
        case "Nanchang": return "南昌"
        case "Hefei": return "合肥"
        case "Fuzhou": return "福州"
        case "Xiamen": return "厦门"
        case "Kunming": return "昆明"
        case "Guiyang": return "贵阳"
        case "Lanzhou": return "兰州"
        case "Xi'an": return "西安"
        case "Xining": return "西宁"
        case "Yinchuan": return "银川"
        case "Nanning": return "南宁"
        case "Haikou": return "海口"
        case "Zhuhai": return "珠海"
        case "Foshan": return "佛山"
        case "Dongguan": return "东莞"
        case "Suzhou": return "苏州"
        case "Wuxi": return "无锡"
        case "Ningbo": return "宁波"
        case "Wenzhou": return "温州"
        case "Changzhou": return "常州"
        case "Zhongshan": return "中山"
        case "Huizhou": return "惠州"
        case "Shantou": return "汕头"
        case "Zhanjiang": return "湛江"
        case "Taizhou": return "台州"
        case "Jiaxing": return "嘉兴"
        case "Shaoxing": return "绍兴"
        case "Yangzhou": return "扬州"
        case "Zhenjiang": return "镇江"
        case "Nantong": return "南通"
        case "Xuzhou": return "徐州"
        case "Luoyang": return "洛阳"
        case "Guilin": return "桂林"
        case "Lhasa": return "拉萨"
        case "Urumqi": return "乌鲁木齐"
        case "Hohhot": return "呼和浩特"
        case "Macau": return "澳门"
        case "Hong Kong": return "香港"
        case "Taipei": return "台北"
        case "Kaohsiung": return "高雄"
        case "Taichung": return "台中"
        case "Tainan": return "台南"
        default: return name
        }
    }

    static func caiyunCondition(_ skycon: String) -> String {
        switch skycon {
        case "CLEAR_DAY", "CLEAR_NIGHT": return "晴"
        case "PARTLY_CLOUDY_DAY", "PARTLY_CLOUDY_NIGHT":
            return "多云"
        case "CLOUDY": return "阴"
        case "LIGHT_RAIN": return "小雨"
        case "MODERATE_RAIN": return "中雨"
        case "HEAVY_RAIN": return "大雨"
        case "STORM_RAIN": return "暴雨"
        case "THUNDER_SHOWER": return "雷阵雨"
        case "SLEET": return "雨夹雪"
        case "LIGHT_SNOW": return "小雪"
        case "MODERATE_SNOW": return "中雪"
        case "HEAVY_SNOW": return "大雪"
        case "STORM_SNOW": return "暴雪"
        case "HAIL": return "冰雹"
        case "LIGHT_HAZE": return "薄雾"
        case "MODERATE_HAZE": return "中度雾"
        case "HEAVY_HAZE": return "浓雾"
        case "FOG": return "雾"
        case "DUST": return "沙尘"
        case "WIND": return "大风"
        default: return skycon
        }
    }

    // GPS：WhenInUse 授权 + 单次定位，5s 超时回 nil。
    private func gpsCoords() async -> (Double, Double)? {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        return await withCheckedContinuation { cont in
            locContinuation = cont
            locResumed = false
            manager.delegate = self
            manager.desiredAccuracy =
                kCLLocationAccuracyKilometer
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: 5_000_000_000)
                self.resumeLoc(nil)
            }
        }
    }

    private func resumeLoc(_ v: (Double, Double)?) {
        guard !locResumed, let c = locContinuation else {
            return
        }
        locResumed = true
        locContinuation = nil
        c.resume(returning: v)
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations
                         locations: [CLLocation]) {
        if let l = locations.first {
            resumeLoc((l.coordinate.latitude,
                       l.coordinate.longitude))
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError
                         error: Error) {
        resumeLoc(nil)
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied
            || manager.authorizationStatus == .restricted {
            resumeLoc(nil)
        }
    }
}

// ── 列表 ───────────────────────────────────────────
/// 首页滚动探针（fix_home_regressions_0957）：直读
/// 承载滚动视图的 contentOffset + adjustedContent-
/// Inset 得「距顶滚动量」，替代旧基线捕获制（旧制
/// 以 spacerRow 几何首读定基线 firstRowMinY：基线
/// 本应在静止于顶时采，却在启动首帧/导航转场等几
/// 何未定帧被首读毒化——误差 ≥30pt 令 compactP
/// 满格、头像与胶囊整隐且命中关死（关门点 = 满
/// 格点，AUD-A-04 阈值对齐后两事同点），
/// 且基线终生不重采、无任何恢复路径，0.9.57 真机
/// 实报 S2/S3）。本探针量测对象即所需量本身：距
/// 顶量 = max(0, offset.y + inset.top)，静止于顶
/// 恒 0、下拉过冲钳 0，无基线、无捕获窗、无可毒
/// 化状态。探针视图挂根 ZStack 背景（与 Editor-
/// NavProbe 同点位族），入窗后经响应链定位自身宿
/// 主控制器、自其视图向下找到首页子树唯一的滚动
/// 视图（窄屏 List / 宽屏 ScrollView 二选一恒在，
/// 编辑器等其它控制器的滚动视图不在本子树内）并
/// KVO 观察；形态切换换滚动视图时经 updateUIView
/// 与有界重试重找；被编辑器覆盖期间探针离窗自动
///  detach、返回时重挂并直读现值（返回瞬间的紧凑
/// 态由滚动视图真值决定，不靠历史状态）。找不到
/// 时只留待后续重试、scrollOffset 保持 0（页眉恒
/// 展开，无害降级），不猜基线。
/// 改判补注（fix_home_header_vanish，0.9.58 用户
/// 装机复报头像/胶囊仍偶尔不见）：直读本身无误，
/// 但旧出口零消毒——attach 同步首读与 KVO 单帧读
/// 数直达呈现层，滚动视图首帧/重挂瞬间 content-
/// Offset 尚未落到静止值（−inset.top）时首读即假
/// 偏移（inset.top≈59 → 距顶量 ≈59，整隐/命中关
/// 死皆可达），且 15–29 的命中带无 Diag 留痕、无
/// 从下手。本批在探针出口加消毒单点（Scroll-
/// OffsetSanitizer：未落定不发布、静止带跨入命中
/// 门带须两读确认、毛刺废弃记 Diag 行），呈现层
/// compactP 收敛为纯函数 HomeHeaderMath（见下）。
struct HomeScrollProbe: UIViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.isUserInteractionEnabled = false
        v.onScroll = onScroll
        return v
    }

    func updateUIView(_ v: ProbeView, context: Context) {
        v.onScroll = onScroll
        v.tryAttach()
    }

    final class ProbeView: UIView {
        var onScroll: ((CGFloat) -> Void)?
        private weak var scrollView: UIScrollView?
        private var offsetObs: NSKeyValueObservation?
        private var insetObs: NSKeyValueObservation?
        /// 出口消毒状态机（fix_home_header_vanish）：
        /// 全部原始读数经它才许发布到呈现层。
        private var sanitizer = ScrollOffsetSanitizer()
        /// 入树等待登记（补丁债偿还批一 A-5）：滚动
        /// 视图未入子树时经 ViewTreeWait 等待，达成
        /// 或离窗时注销；非空即等待中（防重复登记）。
        private var treeWait: ViewTreeWait.Token?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                detach()
            } else {
                tryAttach()
            }
        }

        func tryAttach() {
            guard window != nil else { return }
            if let sv = scrollView, sv.window != nil {
                return
            }
            detach()
            guard let root = owningRootView(),
                  let found = Self.findScroll(root) else {
                // 滚动视图尚未落定（形态切换同周期）：
                // 经入树等待共享工具（ViewTreeWait）等
                // 其入树——逐帧复查、到期（1s，与旧
                // 20×0.05 同预算）静默降级（scroll-
                // Offset 保持 0、页眉恒展开，后续
                // update/入窗仍可再驱动本函数）。旧
                // 定时重试已收口（补丁债偿还批一
                // A-5）。
                if treeWait == nil {
                    treeWait = ViewTreeWait.shared.wait(
                        condition: { [weak self] in
                            guard let self,
                                  let root =
                                    self.owningRootView()
                            else { return false }
                            return Self.findScroll(root)
                                != nil
                        },
                        action: { [weak self] in
                            self?.treeWait = nil
                            self?.tryAttach()
                        })
                }
                return
            }
            if let t = treeWait {
                ViewTreeWait.shared.cancel(t)
                treeWait = nil
            }
            scrollView = found
            let report: (UIScrollView) -> Void = {
                [weak self] sv in
                guard let self else { return }
                self.feed(sv)
            }
            offsetObs = found.observe(
                \.contentOffset, options: [.new]) { sv, _ in
                report(sv)
            }
            insetObs = found.observe(
                \.adjustedContentInset, options: [.new]) {
                sv, _ in
                report(sv)
            }
            report(found)
            // 挂载复读（消毒两读确认的第二读来源之一）：
            // 首读若跨入命中门带未获确认，120ms 后以
            // 落定读数复核——落定值仍在带内即确认发
            // 布（真滚动/挂载时已滚动态），已落回静
            // 止带即按毛刺废弃并记行（首帧假偏移）。
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.12) {
                [weak self, weak found] in
                guard let self, let found,
                      self.scrollView === found else { return }
                self.feed(found)
            }
            DiagLog.shared.log(.info,
                "APP home scrollprobe attach inset="
                + "\(Int(found.adjustedContentInset.top))")
        }

        /// 原始读数入口（KVO 双观察 + 挂载首读/复读
        /// 共用）：距顶量原始值 = contentOffset.y +
        /// adjustedContentInset.top（钳零在消毒器
        /// 内）；布局未落定（bounds 任一维为 0）不
        /// 发布。发布与毛刺废弃均经消毒器单点裁决。
        private func feed(_ sv: UIScrollView) {
            let raw = sv.contentOffset.y
                + sv.adjustedContentInset.top
            let laidOut = sv.bounds.width > 0
                && sv.bounds.height > 0
            let out = sanitizer.feed(raw: raw,
                                     laidOut: laidOut)
            if let peak = out.discardedPeak {
                DiagLog.shared.log(.info,
                    "APP home scrollprobe spike discarded"
                    + " raw=\(Int(peak)) pub="
                    + "\(Int(sanitizer.published))")
            }
            if let d = out.publish {
                onScroll?(d)
            }
        }

        private func detach() {
            offsetObs?.invalidate()
            offsetObs = nil
            insetObs?.invalidate()
            insetObs = nil
            scrollView = nil
            sanitizer = ScrollOffsetSanitizer()
            if let t = treeWait {
                ViewTreeWait.shared.cancel(t)
                treeWait = nil
            }
        }

        /// 自身宿主控制器的根视图（响应链上行，与
        /// EditorNavProbe 同走法）：搜索域限于本控
        /// 制器子树，编辑器/设置等被 push 的控制器
        /// 各有其根、不入本域。
        private func owningRootView() -> UIView? {
            var r: UIResponder? = self
            while let cur = r {
                if let vc = cur as? UIViewController {
                    return vc.view
                }
                r = cur.next
            }
            return nil
        }

        /// 目标滚动视图选取（fix_home_header_vanish
        /// 硬化）：子树内面积最大者——承载面恒为全
        /// 屏主滚动面，嵌套小滚动面（若日后卡内容
        /// 引入）不得夺目标；全员 bounds 未定（面积
        /// 皆 0）时先序首个胜出（祖先即承载面，与
        /// 旧先序语义同结果）。
        private static func findScroll(_ v: UIView)
            -> UIScrollView? {
            var best: UIScrollView?
            var bestArea: CGFloat = -1
            func visit(_ v: UIView) {
                if let sv = v as? UIScrollView {
                    let a = sv.bounds.width
                        * sv.bounds.height
                    if a > bestArea {
                        bestArea = a
                        best = sv
                    }
                }
                for sub in v.subviews { visit(sub) }
            }
            visit(v)
            return best
        }
    }
}

/// 页眉紧凑进度纯函数（fix_home_header_vanish 收
/// 敛为单源）：硬不变量——距顶量 ≤0 恒 0（静止于
/// 顶页眉恒展开）、≥30 恒 1、其间线性。逐档期望：
/// −10→0、0→0、7.5→0.25、15→0.5、30→1、90→1
/// （纯函数执行实证见 fix_home_header_vanish.md）。
enum HomeHeaderMath {
    static func compactP(forOffset d: CGFloat)
        -> CGFloat {
        min(max(d / 30, 0), 1)
    }

    /// 首组头顶距动态规则（AUD-A-08，用户
    /// 2026-11-28 裁定动态适应，fix_home_
    /// header_gap_adaptive）：组头文字顶与上方
    /// 相邻可见元素底之间的视觉间隔恒等于基准
    /// 节奏，不再由各邻居态各写死一个合成数。
    /// 账面（窄屏 List，首组头邻域占位）：
    /// spacer 占位行 insets 0/0、横幅行 0/6、
    /// notice 行 0/6、新建卡行 3/3、组头行
    /// top=T/bottom 3；间隔 = 紧邻行 bottom
    /// inset + T（行距由 insets 唯一合成——
    /// F30-13 零默认依赖锁；组头 Text 无内
    /// padding、行顶≈文字顶，与既有 28/6 账
    /// 同近似）。基准节奏 28 = Web 组间合成
    /// 定案值（前卡 bottom 3 + 组头 top 25，
    /// 见 groupHeader 账）。旧合成：常态
    /// 3+25=28、横幅/notice 紧邻 6+25=31、
    /// loadFailed 时 spacer 紧邻 0+25=25——
    /// 三态漂移。本式以紧邻行 bottom 为唯一
    /// 输入反推 T：T = max(28 − b, 3)，间隔
    /// = b + T ≥ 28 恒成立（横幅强视觉块在
    /// 位时间隔不低于无横幅态、不贴脸）；
    /// 下限 3 = 本 List 卡行 top inset 同值
    /// （行间最小呼吸），仅当 b > 25 的未
    /// 来邻居出现时触发钳制、现行四邻居均
    /// 不触发。补偿项 22（横幅态）= 28 −
    /// 横幅行自身 bottom 6，逐项可追溯、
    /// 非另加数。量测断言见 verify [57]。
    static let groupRhythm: CGFloat = 28
    static let groupTopFloor: CGFloat = 3
    static func firstGroupTopInset(
        aboveBottomInset b: CGFloat) -> CGFloat {
        max(groupRhythm - b, groupTopFloor)
    }
    static func firstGroupGap(
        aboveBottomInset b: CGFloat) -> CGFloat {
        b + firstGroupTopInset(aboveBottomInset: b)
    }
}

/// 距顶量出口消毒状态机（fix_home_header_vanish）：
/// HomeScrollProbe 的全部原始读数经此单点才许发
/// 布到呈现层。病灶：旧出口零消毒——attach 同步
/// 首读/KVO 单帧读数直达 @Published，滚动视图首
/// 帧/重挂瞬间 contentOffset 未落静止值时的假偏
/// 移（可达 inset.top 全量 ≈59）一帧即整隐页眉，
/// 且无从判读。本状态机三条机制：
/// ① 未落定不发布：布局未定（bounds 任一维 0）
/// 的读数整批丢弃；
/// ② 两读确认：已发布值在静止带（<30，compactP
/// <1、命中门未关）时，单读跨入命中门带（≥30）
/// 只记候选不发布，须下一读（KVO 续报或挂载复
/// 读）仍在带内才确认发布——真滚动的 KVO 序列
/// 稠密、确认只迟一读；孤立毛刺无第二读、随即
/// 被回落读废弃。带内移动与回落发布不设确认
/// （迟滞只加在「关门」方向）；
/// ③ 毛刺留痕：候选被回落读废弃时经 discarded-
/// Peak 报出，由探针记 Diag 行（真机再犯凭导
/// 出定因，不靠抓现行）。
/// 发布死区 0.5（沿旧探针口径）。逐序列期望
/// （发布列，门带 30 口径）：[0,59,0]→{0} +
/// 废弃 59；[0,8,25,60,120]→{8,25,120}；
/// [0,5,10,14,16,20,40]→{5,10,14,16,20}（40
/// 只记候选未确认）；[200,200]→{200}（挂载
/// 复读确认）；[100,0]→{0} + 废弃 100（回落
/// 即时）。序列随 AUD-A-04 门带 15→30 改判
/// 重算；机制实证见 fix_home_header_vanish.md。
struct ScrollOffsetSanitizer {
    /// 命中门带下界：距顶量 ≥30 ⇔ compactP ≥1
    /// ⇔ 头像/胶囊命中关门（呈现后果带）。
    /// 与页眉命中阈值同值联动（AUD-A-04 改判：
    /// 旧值 15 ⇔ p≥0.5 关门、页眉 [0.5,1) 成
    /// 命中死区；阈值对齐 p<1 后关门点即满格
    /// 点，本带随之改判 30，两处勿单独改）。
    static let hitGateBand: CGFloat = 30
    static let deadband: CGFloat = 0.5
    private(set) var published: CGFloat = 0
    private var candidate: CGFloat?

    struct Output {
        var publish: CGFloat?
        var discardedPeak: CGFloat?
    }

    mutating func feed(raw: CGFloat, laidOut: Bool)
        -> Output {
        var out = Output()
        guard laidOut else { return out }
        let d = max(0, raw)
        if d < Self.hitGateBand {
            // 静止带/回落：即时发布；待确认候选被
            // 回落废弃 = 孤立毛刺，报峰值留痕。
            if let peak = candidate {
                candidate = nil
                out.discardedPeak = peak
            }
            if abs(d - published) >= Self.deadband
                || out.discardedPeak != nil {
                published = d
                out.publish = d
            }
            return out
        }
        if published >= Self.hitGateBand {
            // 带内移动：无确认、死区过滤后即时发布。
            if abs(d - published) >= Self.deadband {
                published = d
                out.publish = d
            }
            return out
        }
        // 静止带 → 命中门带跨入：两读确认。
        if candidate != nil {
            candidate = nil
            published = d
            out.publish = d
        } else {
            candidate = d
        }
        return out
    }
}

struct ListView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var langStore: LangStore
    @ObservedObject private var weather =
        WeatherService.shared
    @StateObject private var nav = NavState()
    @StateObject private var groupsCache = GroupsCache()
    /// 首页行帧通道（U5）：行 GeometryReader 回报
    /// （window 坐标），供 home.row 注册面的
    /// frameInWindow 与 P4 home_geometry 探针量
    /// 测；纯存储盒（无 @Published，写不触发重演
    /// 算，与 GroupsCache 同例），键 = memo.id。
    final class RowFrameStore: ObservableObject {
        var frames: [String: CGRect] = [:]
    }
    @StateObject private var rowFrameStore =
        RowFrameStore()
    /// 首页行注册对账盒（fix_home_row_registry）：
    /// home.row 注册/注销改由 syncRowRegistry 按
    /// 呈现行集对账单点管辖，本盒只存已管辖行
    /// 的注册 owner（id → UUID）；纯存储盒（无
    /// @Published，与 RowFrameStore 同例）。旧
    /// 制注册/注销挂在行视图的锚点 update/
    /// dismantle 上——即 List 细胞实现/拆卸时
    /// 机：新建行场景窗内未注册、删行条目残留
    /// 成幽灵行且帧永不清（0.9.64 U5 三景 +
    /// home_geometry 探针实跑实证），故废锚点
    /// 制、注册真值源改回呈现行集本身。
    final class RowRegistryStore: ObservableObject {
        var owners: [String: UUID] = [:]
    }
    @StateObject private var rowRegistryStore =
        RowRegistryStore()
    /// 搜索输入焦点 = 搜索胶囊展开态的单一真相
    /// （Web onblur 收起同构）：胶囊开合只由此派
    /// 生，任何让键盘消失的路径（回车 onSubmit、
    /// 滚动收起、离开首页、清除）都经辞焦收敛到
    /// 同一状态，不再有独立的开合标志可脱钩（旧
    /// searchOpen 标志只有清除钮一个关写者，回车
    /// 辞焦后胶囊永停展开态——用户实报）。
    @FocusState private var searchFocused: Bool

    /// 归组缓存键：归组的全部输入面——memos/manifest
    /// 版本（Library 写点同步 bump）、搜索命中集、语
    /// 言（组标题经语言包解析，切换即失效）。
    struct GroupsKey: Equatable {
        var memos: Int
        var manifest: Int
        var hits: [String]?
        var lang: String
    }

    /// 归组结果缓存（引用盒，跨 ListView 值重构存续；
    /// @StateObject 持有故须 ObservableObject，与
    /// NavState 同例——无 @Published，纯存储盒）。
    final class GroupsCache: ObservableObject {
        var key: GroupsKey?
        var value: [MemoGroup] = []
    }
    // 文字大小跟随系统 Dynamic Type（Web 分级是无系统
    // API 时的替代口径，原生走更优路）。
    @ScaledMetric(relativeTo: .body)
    private var groupFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body)
    private var metaFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .body)
    private var titleFontScale: CGFloat = 1.0
    // 文字大小跟随系统（Dynamic Type 全量实装，
    // 续既有三枚 ScaledMetric 口径补齐本视图余面）。
    @ScaledMetric(relativeTo: .largeTitle)
    private var f44: CGFloat = 44
    @ScaledMetric(relativeTo: .title3)
    private var f19: CGFloat = 19
    @ScaledMetric(relativeTo: .caption2)
    private var f11: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2)
    private var f10: CGFloat = 10
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17

    final class NavState: ObservableObject {
        @Published var dest: Dest?
        /// 编辑器转场宿主（0.9.50 呈现重构）：新建/打
        /// 开/关联打开三路呈现都经它以 UIKit push 承
        /// 载（见 MomentEditorTransition.swift）；导航
        /// 控制器由 EditorNavProbe 在根视图入窗后登记。
        let editorHost = EditorTransitionHost()
        @Published var query = ""
        /// 搜索胶囊收起来源（Diag 归因，纯记账不发
        /// 布）：程序化辞焦前由发起方写明（submit/
        /// clear/nav），系统侧辞焦（滚动收起等）走
        /// 默认 system；胶囊状态本体不存于此——由
        /// ListView 的 @FocusState 单一派生（见
        /// searchCapsule 与 fix_home_search_layout）。
        var searchCloseSrc = "system"
        @Published var expandedKeys: Set<String> = []
        /// 距顶滚动量（页眉紧凑进度 compactP 的唯一
        /// 输入）：由 HomeScrollProbe 直读承载滚动视
        /// 图的 contentOffset + adjustedContentInset
        /// 写入（fix_home_regressions_0957 替代旧基
        /// 线捕获制——基线字段 firstRowMinY 已退役
        /// 删除，零残留）。
        @Published var scrollOffset: CGFloat = 0
        /// 首页宽屏网格形态（Web 口径自带判定：宽≥768
        /// 或横屏且高≤560，与编辑页宽屏判定不同）。
        @Published var homeWide = false
        @Published var homeCols = 3
        /// 首页容器实测宽（≥1280 页眉同轴约束用，
        /// C-A4；0 = 未量测、页眉回退 20）。
        @Published var homeW: CGFloat = 0
    }

    /// 栈内目的地（0.9.50 起只剩设置）：编辑器呈现已
    /// 移交 EditorTransitionHost 的 UIKit push，旧
    /// .editor 目的地退役删除（零残留）。
    enum Dest: Identifiable {
        case settings
        var id: String { "settings" }
    }

    var visibleMemos: [MemoItem] {
        guard let hits = library.searchHits else {
            return library.memos
        }
        return library.memos.filter { hits.contains($0.id) }
    }

    struct MemoGroup: Identifiable {
        let id: String
        let title: String
        let memos: [MemoItem]
        // 附件清单名表/MIME 表（组装时由 ListView
        // 注入，图文卡判定按清单判图需要：名兜底、
        // MIME 优先）。
        let manifestNames: [String: String]
        let manifestTypes: [String: String]
        // 图/文分区在组装时一次算清（存量属性）：
        // 此前 images/texts 为计算属性，ListView
        // 每次 body 求值对每组各访问两次（sublist
        // 实参 + isEmpty 检查），每次访问都对全组
        // 备忘重跑 hasImageShape（块扫描 + hasCover
        // 全树探针）——单次 body 即 4 趟全库节点遍
        // 历，且新建点按的同一轮更新里正撞上（转
        // 场首帧前的主线程长尾，见 fix_new_note_
        // transition）。分区口径与原计算属性逐项
        // 等价（同谓词、同序）。
        let images: [MemoItem]
        let texts: [MemoItem]

        init(id: String, title: String,
             memos: [MemoItem],
             manifestNames: [String: String],
             manifestTypes: [String: String]) {
            self.id = id
            self.title = title
            self.memos = memos
            self.manifestNames = manifestNames
            self.manifestTypes = manifestTypes
            var imgs: [MemoItem] = []
            var txts: [MemoItem] = []
            for m in memos {
                if m.hasImageShape(names: manifestNames,
                                   types: manifestTypes) {
                    imgs.append(m)
                } else {
                    txts.append(m)
                }
            }
            images = imgs
            texts = txts
        }
    }

    /// 归组（0.9.48 根治 S1 的趟基数）：按输入版本读
    /// 缓存——body 每趟重演算时版本未变直接回缓存，
    /// 不再逐篇重跑日期解析与封面探针；版本一变才
    /// 整组重装一趟（assembleGroups）。旧实现是 body
    /// 内计算属性：转场窗内点按发布与头像缓存发布
    /// 各引爆一趟全库重算（T2/T7，第二轮排查定案）。
    var groups: [MemoGroup] {
        let key = GroupsKey(
            memos: library.memosVersion,
            manifest: library.manifestVersion,
            hits: library.searchHits,
            lang: langStore.code)
        if groupsCache.key == key {
            return groupsCache.value
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        let value = assembleGroups()
        if library.createTraceActive {
            let ms = Int((CFAbsoluteTimeGetCurrent()
                - t0) * 1000)
            library.createTraceListPasses += 1
            library.createTraceListMs += ms
            DiagLog.shared.log(.info,
                "CREATE listpass "
                + "n=\(library.createTraceListPasses) "
                + "ms=\(ms)")
        }
        groupsCache.key = key
        groupsCache.value = value
        return value
    }

    /// 归组按 createdAt（Web 口径）：置顶/今天/昨天/过去
    /// 7天/过去30天/{m}月（同年）/{y}年（跨年）。
    private func assembleGroups() -> [MemoGroup] {
        let pinned = visibleMemos.filter { $0.pinned }
        let rest = visibleMemos.filter { !$0.pinned }
        var out: [MemoGroup] = []
        if !pinned.isEmpty {
            out.append(MemoGroup(
                id: "pinned", title: Lang.t("group.pinned"),
                memos: pinned,
                manifestNames: library.attachmentNames,
                manifestTypes: library.attachmentTypes))
        }
        let cal = Calendar.current
        let now = Date()
        // 归组键与语言无关（组 id / 展开键在语言切换
        // 前后稳定），标题在组装时经语言包解析。
        func bucket(_ d: Date) -> String {
            let days = cal.dateComponents(
                [.day], from: cal.startOfDay(for: d),
                to: cal.startOfDay(for: now)).day ?? 999
            if days <= 0 { return "today" }
            if days == 1 { return "yesterday" }
            // 边界含端点（H1）：Web section_label 与
            // 归档原版两真源同为 diff ≤7 入「过去
            // 7天」、≤30 入「过去30天」；此前 <7/<30
            // 把恰 7/30 天整的备忘错分下一档。
            if days <= 7 { return "week" }
            if days <= 30 { return "month" }
            let y = cal.component(.year, from: d)
            if y == cal.component(.year, from: now) {
                return "m-\(cal.component(.month, from: d))"
            }
            return "y-\(y)"
        }
        func bucketTitle(_ key: String) -> String {
            switch key {
            case "today": return Lang.t("group.today")
            case "yesterday":
                return Lang.t("group.yesterday")
            case "week": return Lang.t("group.week")
            case "month": return Lang.t("group.month")
            default:
                if key.hasPrefix("m-") {
                    return Lang.tf(
                        "group.month_of_year",
                        ["m": String(key.dropFirst(2))])
                }
                return Lang.tf(
                    "group.year",
                    ["y": String(key.dropFirst(2))])
            }
        }
        // 组序 = 扫描遇见序（审计二轮小差 6）：Web
        // build_groups 按标签遇见序成组、归档
        // groupedItems 同口径。rest 沿库序（置顶
        // 在前、其余 updatedAt 倒序）扫描，桶按首
        // 次遇见的先后成序——常态下与时序桶序一
        // 致；编辑旧篇时其 createdAt 桶随扫描位被
        // 顶到前面，与两真源一致。此前固定桶序在
        // 该场景分叉。
        var byBucket: [String: [MemoItem]] = [:]
        var names: [String] = []
        for m in rest {
            let b = bucket(m.bucketDate)
            if byBucket[b] == nil { names.append(b) }
            byBucket[b, default: []].append(m)
        }
        for name in names {
            if let g = byBucket[name], !g.isEmpty {
                out.append(MemoGroup(
                    id: name, title: bucketTitle(name),
                    memos: g,
                    manifestNames: library.attachmentNames,
                    manifestTypes: library.attachmentTypes))
            }
        }
        return out
    }

    // 首页形态对齐 Web 原版：自定义页眉（右上玻璃动作钮 +
    // 34/800 大标题）+ 玻璃搜索胶囊 + 新建卡 + 分组胶囊卡。
    // 滚动/左滑用原生 List（无 Section，梯子定案禁区）。
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if nav.homeWide {
                    gridHome
                } else {
                List {
                    spacerRow
                    if library.isReadOnly {
                        readonlyBannerRow
                    }
                    if !library.notice.isEmpty {
                        noticeRow
                    }
                    if !library.loadFailed && !library.isReadOnly {
                        newCardRow
                    }
                    ForEach(groups) { group in
                        // 首组头顶距走动态规则（紧邻
                        // 行随横幅/notice/loadFailed
                        // 变，AUD-A-08）；后续组头紧
                        // 邻恒为前组末卡（bottom 3）、
                        // 同式算得 25（见 groupHeader）。
                        groupHeader(
                            group.title,
                            topInset: HomeHeaderMath
                                .firstGroupTopInset(
                                    aboveBottomInset:
                                        group.id
                                            == groups.first?.id
                                        ? firstGroupAboveBottomInset
                                        : 3))
                        sublist(group: group, kind: "img",
                                memos: group.images)
                        if !group.images.isEmpty
                            && !group.texts.isEmpty {
                            // 图/文子列间隔（C-A3，账
                            // 面 2026-11-27 二次核正，
                            // fix_home_regressions_
                            // 0957）：Web 交界逐项 =
                            // .img-card margin-bottom
                            // 0（其在 .swipe-wrapper
                            // 内恒为末子、:last-child
                            // 归零）+ .swipe-wrapper
                            // margin-bottom 6 + .gap-
                            // 16 高 16 = 卡缘到卡缘
                            // 22（base.css:118/191-
                            // 192/205，main.rs gap-16
                            // 插入点）。旧账「margin
                            // 24 + gap 16 = 40」误把
                            // .list-group 的组间
                            // margin-bottom 24 记到
                            // 子列交界上、本行据此定
                            // 高 34——0.9.57 的 insets
                            // 归零只治了默认继承段，
                            // 账面本身多记 18，用户
                            // 装机仍报偏大。原生合成
                            // = 上卡 inset 3 + 本行
                            // 16 + 下卡 inset 3 = 22：
                            // insets 3+3 顶 Web 的
                            // wrapper margin 6（与子
                            // 列内卡间距同值同源），
                            // 本行只补 gap-16 本体
                            // （高度见下改判）。本行
                            // 须显式零
                            // insets：0.9.36 落码时
                            // 漏写，系统默认 insets
                            // 被静默继承（纵向合计
                            // 32），实测合成 72——
                            // 用户 0.9.56 实报（定案
                            // fix_home_card_spacing.
                            // md）。本 List 全行显式
                            // 声明 insets、零默认依
                            // 赖，由 verify F30-13 计
                            // 数锁守；合成值由 F30-14
                            // 锚。改判（用户 2026-
                            // 11-27 真机观感裁定，
                            // fix_home_grid_land-
                            // scape）：卡缘到卡缘
                            // 22 → 12，覆盖 Web
                            // parity 的 22（上账留
                            // 痕不删）；本行高按新
                            // 账反推 = 12 − 3 − 3
                            // = 6。同子列内卡间距
                            // （insets 3+3 = 6）与
                            // 网格 gap 14 不在此裁
                            // 定面、未动。
                            Color.clear
                                .frame(height: 6)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        sublist(group: group, kind: "txt",
                                memos: group.texts)
                    }
                    if !visibleMemos.isEmpty {
                        // 列表底部留白（C-A8）：末卡
                        // inset 3 + 本行 17 = 20（Web
                        // .container padding-bottom）。
                        Color.clear
                            .frame(height: 17)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    // 空态就绪门（fix_splash_flash_
                    // sequence）：未 didLoad 时空态不
                    // 可达——加载中与真空库是两件事，
                    // 首帧起只呈页眉与底色，杜绝间隙
                    // 帧露出「空库」假象（宽屏 grid
                    // Empty 同门）。
                    if visibleMemos.isEmpty
                        && library.didLoad {
                        emptyRow
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .scrollContentBackground(.hidden)
                }
                header
                if library.pendingDeletion != nil {
                    undoToast
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .bottom)
                }
            }
            // 自检驱动注册（U5）：首页根面——状态
            // 读（搜索/命中/紧凑派生/目的地/空态/
            // 待删）与动作同体（focusSearch =
            // activateSearch 具名入口、setText =
            // 搜索字段 Binding 的 set 同式、行动作
            // 见 home.row）；closeDest 为导航绑定
            // 写（系统返回的等价写面，非业务动作）。
            .background(UITestAnchor(
                providesFrame: false) {
                UITestSurfaceEntry(
                    id: "home.view", kind: "page",
                    instance: "-",
                    actions: [
                        "focusSearch": { _ in
                            activateSearch()
                        },
                        "blurSearch": { _ in
                            nav.searchCloseSrc = "system"
                            searchFocused = false
                        },
                        "submitSearch": { _ in
                            nav.searchCloseSrc = "submit"
                            searchFocused = false
                        },
                        "tapAvatar": { _ in
                            resignSearch()
                            nav.dest = .settings
                        },
                        "closeDest": { _ in
                            nav.dest = nil
                        },
                        "undoDelete": { _ in
                            library.undoDeletion()
                        },
                    ],
                    state: [
                        "query": { nav.query },
                        "searchFocused": {
                            searchFocused
                                ? "true" : "false"
                        },
                        "hitsActive": {
                            library.searchHits != nil
                                ? "true" : "false"
                        },
                        "hitsCount": {
                            library.searchHits.map {
                                "\($0.count)"
                            } ?? ""
                        },
                        "visibleCount": {
                            "\(visibleMemos.count)"
                        },
                        "totalCount": {
                            "\(library.memos.count)"
                        },
                        "compactP": {
                            "\(HomeHeaderMath.compactP(forOffset: nav.scrollOffset))"
                        },
                        "scrollOffset": {
                            "\(nav.scrollOffset)"
                        },
                        "wide": {
                            nav.homeWide
                                ? "true" : "false"
                        },
                        "cols": { "\(nav.homeCols)" },
                        "dest": { nav.dest?.id ?? "" },
                        "avatarShown": { "true" },
                        "emptyShown": {
                            (visibleMemos.isEmpty
                             && library.searchHits != nil)
                                ? "true" : "false"
                        },
                        "emptyLibrary": {
                            library.memos.isEmpty
                                ? "true" : "false"
                        },
                        "pendingDeletionId": {
                            library.pendingDeletion?.id
                                ?? ""
                        },
                        "readOnly": {
                            library.isReadOnly
                                ? "true" : "false"
                        },
                        "noticeShown": {
                            !library.notice.isEmpty
                                ? "true" : "false"
                        },
                    ],
                    setText: { q in
                        nav.query = q
                        library.search(q)
                    })
            })
            // 行注册对账触发（fix_home_row_
            // registry）：在位即对账一次，其后呈
            // 现行集签名一变即对账（签名 = 呈现
            // 行 id/形态/判图串，见 rowSyncSigna-
            // ture）；离场全注销。注册真值不经
            // 行视图生命周期。
            .onAppear { syncRowRegistry() }
            .onChange(of: rowSyncSignature) { _ in
                syncRowRegistry()
            }
            .onDisappear { clearRowRegistry() }
            .animation(.spring(response: 0.28,
                               dampingFraction: 0.86),
                       value: library.pendingDeletion?.id ?? "")
            // 搜索胶囊状态迁移打点（展开/回缩各一
            // 行、回缩带来源）：供桥 diag_tail 复核
            // 「键盘消失 ⇒ 胶囊回缩」的同源关系。
            .onChange(of: searchFocused) { open in
                if open {
                    DiagLog.shared.log(.info,
                        "APP search capsule open")
                } else {
                    DiagLog.shared.log(.info,
                        "APP search capsule close src="
                        + nav.searchCloseSrc)
                    nav.searchCloseSrc = "system"
                }
            }
            // 页眉紧凑态迁移打点（fix_home_regres-
            // sions_0957，与编辑页 dockflip 同式）：
            // 头像/胶囊的可见与命中全由 compactP 决
            // 定，其迁移必须在 Diag 可判读——旧基线
            // 制下紧凑态为何卡死无一行证据。此后判
            // 读：静止于顶应恒为 compact 0；出现
            // compact 1 先看同窗 scrollprobe attach
            // 行与 offset 值再定性。
            .onChange(of: compactP >= 1) { c in
                DiagLog.shared.log(.info,
                    "APP home compact \(c ? 1 : 0) "
                    + "offset=\(Int(nav.scrollOffset))")
            }
            // 静止带边沿打点（fix_home_header_van-
            // ish 补全判读面）：旧打点只有满紧凑
            // 0↔1 一条边，中间带（距顶 1–29、消毒
            // 两读确认区；AUD-A-04 前此带后半段
            // 为命中死区）迁移无任何留痕——用户
            // 复报「偶尔不见」时无从
            // 分型。本行记 compactP 离/入 0 的边
            // 沿（带当时距顶量）：静止于顶应恒无
            // 本行；出现 0->p 先看同窗 scrollprobe
            // spike discarded 行有无再定性（有 =
            // 毛刺已被消毒挡下、呈现异常另有其
            // 因；无且 offset 大 = 真滚动或探针
            // 目标漂移）。
            .onChange(of: compactP == 0) { atTop in
                DiagLog.shared.log(.info,
                    "APP home compactband "
                    + (atTop ? "->0" : "0->p")
                    + " offset=\(Int(nav.scrollOffset))")
            }
            .overlay {
                // 首页宽屏判定量测（Web 口径）：宽≥768
                // 或横屏且高≤560 进网格；列数 ≥1280 四列。
                GeometryReader { geo in
                    Color.clear
                        .onAppear { syncHomeSize(geo.size) }
                        .onChange(of: geo.size) { s in
                            syncHomeSize(s)
                        }
                }
                .allowsHitTesting(false)
            }
            .background(T.bg)
            // 转场宿主的导航控制器登记（0.9.50）：探针
            // 入窗后沿响应链找到本 NavigationStack 的
            // UINavigationController 交给宿主，此后编
            // 辑器呈现由宿主以 UIKit push 承载。
            .background(EditorNavProbe { nc in
                nav.editorHost.attach(navController: nc)
                // 桥导航通道接线（U0 地基，与 attach
                // 同点位、幂等）：桥侧经通道请求开/关
                // 编辑器，走宿主 pushEditor 正规路径；
                // 安全模式下本视图不构建、通道恒未接线。
                BridgeNavigationChannel.shared.wire(
                    host: nav.editorHost,
                    library: library) { item in
                    openLinkedMemo(item)
                }
                // 在席边界辞焦接线（fix_home_regres-
                // sions_0957，与上同点位、幂等覆盖）：
                // 编辑器会话开始（seat 是手指/桥/关联
                // 全部呈现路径的单点）即收敛搜索焦
                // 点——桥路径直调宿主 push、不经首页
                // 各辞焦点，焦点若残存于编辑器之下，
                // 返回时被 SwiftUI 焦点系统重新施加、
                // 首页无点按自弹键盘（S1）。不变量在
                // 会话边界收口，不逐路径补辞焦。
                EditorSeatRegistry.shared.onSeatChange = {
                    seated in
                    if seated { resignSearch(src: "seat") }
                }
            })
            // 首页滚动探针接线（fix_home_regres-
            // sions_0957）：距顶滚动量直读滚动视图
            // 真值写 nav.scrollOffset（compactP 唯
            // 一输入），见 HomeScrollProbe。
            .background(HomeScrollProbe { d in
                nav.scrollOffset = d
            })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { nav.dest != nil },
                set: { if !$0 { nav.dest = nil } })) {
                switch nav.dest {
                case .settings:
                    SettingsView(library: library)
                case nil:
                    EmptyView()
                }
            }
            .onAppear {
                Library.markScene(LaunchStep.sceneHome)
                library.markFirstFrame()
                if library.memos.isEmpty { library.load() }
                // S13 guard 点：指令点名天气自动刷新
                // 即跳过（天气块走既有缓存/手动刷新）。
                if OpsDirectives.cached().isDisabled(
                    OpsStep.weatherRefresh) {
                    DiagLog.shared.logOnce(
                        "ops-skip-weather", .info,
                        "OPS skip step="
                        + OpsStep.weatherRefresh)
                } else {
                    WeatherService.shared.refreshIfNeeded()
                }
            }
        }
    }

    private func syncHomeSize(_ s: CGSize) {
        if s.width != nav.homeW { nav.homeW = s.width }
        let wide = s.width >= 768
            || (s.width > s.height && s.height <= 560)
        if wide != nav.homeWide {
            nav.homeWide = wide
            // 形态切换 = 承载滚动视图整体替换：距顶
            // 量归零，新容器由 HomeScrollProbe 重挂
            // 后直读其真值（无基线可重捕，fix_home_
            // regressions_0957）。
            nav.scrollOffset = 0
        }
        let cols = s.width >= 1280 ? 4 : 3
        if cols != nav.homeCols { nav.homeCols = cols }
    }

    /// 离开首页前的搜索辞焦（Web input 失焦即收
    /// 起胶囊的同构点）：打开/新建备忘、进设置都经
    /// 此收敛——辞焦后胶囊由焦点派生自动回缩、查
    /// 询词保留（与 Web 一致）。来源记账供 Diag
    /// 归因（见 body 的 onChange 打点）。src 区分
    /// 调用面：手指路径（新建/打开/头像/紧凑标题）
    /// 用缺省 nav；在席边界（EditorSeatRegistry
    /// onSeatChange 钩子，覆盖桥直调宿主 push 等不
    /// 经手指路径的呈现）用 seat——两面共用同一收
    /// 敛本体，不另立第二套辞焦（fix_home_regres-
    /// sions_0957）。
    private func resignSearch(src: String = "nav") {
        if searchFocused {
            nav.searchCloseSrc = src
            searchFocused = false
        }
    }

    /// 搜索展开具名入口（手指点按与 U5 驱动共用
    /// 同一闭包）：点按到达即记 tap 行——与 body
    /// onChange 的 open/close 行构成三段定位（无
    /// tap = 命中未达；有 tap 无 open = 置焦未立；
    /// 有 open 无 close = 辞焦链断）。置焦的目标
    /// 字段恒在层级（searchCapsule 常驻层），请
    /// 求不因目标缺席被吞（fix_search_tap_dead）。
    private func activateSearch() {
        DiagLog.shared.log(.info,
            "APP search capsule tap")
        searchFocused = true
    }

    /// 新建入口收敛（0.9.50）：四处新建（窄屏空态/新
    /// 建行/宽屏新建卡/宽屏空态）原为同形态五步散写，
    /// 收敛于此——建篇 → 模型 → 落焦意图 → 宿主呈现。
    /// 整个回合包在 disablesAnimations 事务里：新篇入
    /// 列的 List 差分插入不带任何动画，杜绝行插入动
    /// 画与编辑器转场同窗共演（呈现重构定案项）；呈
    /// 现本体经宿主 UIKit push（pushEditor 内记
    /// CREATE dest 戳，时点与旧置位点同回合）。
    private func createAndOpen() {
        // 只读入口守卫（救援完整性批，P2-5）：新建
        // 四路收敛于此，只读态一律拦截 + 提示。
        guard !library.readonlyEntryBlocked("create")
        else { return }
        resignSearch()
        var tx = Transaction(animation: nil)
        tx.disablesAnimations = true
        withTransaction(tx) {
            let item = library.create()
            let ed = EditorModel(item: item, library: library)
            ed.wantsInitialFocus = true
            nav.editorHost.pushEditor(ed, kind: "create") {
                item in openLinkedMemo(item)
            }
        }
    }

    /// 打开既有篇（行/卡点按与右键菜单同路）。
    private func openMemo(_ memo: MemoItem) {
        // 只读入口守卫（救援完整性批，P2-5）：列表
        // 卡/网格卡/搜索结果点按与菜单「打开」全经
        // 此漏斗，只读态一律拦截 + 提示，不进编辑页。
        guard !library.readonlyEntryBlocked("open")
        else { return }
        resignSearch()
        nav.editorHost.pushEditor(
            EditorModel(item: memo, library: library),
            kind: "open") { item in
            openLinkedMemo(item)
        }
    }

    /// 编辑器内关联打开（反链/wiki）：宿主以无动画替
    /// 换栈顶承载（旧同层换 dest 的等价形态）。
    private func openLinkedMemo(_ item: MemoItem) {
        nav.editorHost.replaceTopEditor(
            EditorModel(item: item, library: library)) {
            next in openLinkedMemo(next)
        }
    }

    /// 列表首行占位（悬浮页眉的高度补偿）：纯占
    /// 位行——旧版兼作滚动探针本体（几何首读定基
    /// 线）的职责已随基线制退役移交 HomeScroll-
    /// Probe（fix_home_regressions_0957），本行不
    /// 再带任何量测。
    /// 占位账（2026-11-27 复核，fix_home_search_
    /// layout 线 B）：首卡顶目标 = 头像底（顶距 7
    /// + 头像 72 = 79）+ Web 头像下间距 56（.page-
    /// title 底 padding 10 + .container 顶 padding
    /// 46，base.css:76-88/108）= safe+135；本行
    /// 132 + 首行 top inset 3 = 135。旧值 88 只补
    /// 页眉框 82 + 6，头像下间距被吃掉 44 —— 新建
    /// 卡几乎贴着页眉（用户实报「快顶到顶」）；悬
    /// 浮结构本身是 0.9.23 定案、保留，吃掉的纯间
    /// 距段在此补回。网格态占位行同账、值 135
    /// （网格无首行 inset，见 gridHome 注记）。

    /// 首组头紧邻行 bottom inset（AUD-A-08 动态
    /// 规则的唯一输入）：按 body 行序自组头向上
    /// 穷尽——新建卡在位（条件与 body 字面同
    /// 源）时紧邻恒为新建卡（bottom 3）；否则
    /// notice 行在横幅行之下、紧邻组头（6）；
    /// 再否则横幅行（6）；皆无 = loadFailed
    /// 态占位行紧邻（0）。行 bottom 值与各行
    /// 定义单点同源，verify [57] 由定义处提
    /// 取实测值喂量测断言、不另抄数。
    private var firstGroupAboveBottomInset: CGFloat {
        if !library.loadFailed && !library.isReadOnly {
            return 3
        }
        if !library.notice.isEmpty { return 6 }
        if library.isReadOnly { return 6 }
        return 0
    }

    private var spacerRow: some View {
        Color.clear
            .frame(height: 132)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private var noticeRow: some View {
        Text(library.notice)
            .font(.system(size: f12))
            .foregroundStyle(T.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20,
                                      bottom: 6, trailing: 20))
    }

    /// 只读横幅内容（S4，列表/宽屏共用）：常驻告知
    /// + 回安全模式页出口。退出只读的唯一路径 =
    /// 回页后点「尝试正常启动」（prepareNormalStart
    /// 复位），横幅本身不提供切可写钮（防误触）。
    private var readonlyBannerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: f11))
                .foregroundStyle(T.warning)
            Text(Lang.t("rescue.readonly_banner"))
                .font(.system(size: f12, weight: .semibold))
                .foregroundStyle(T.textMain)
            Spacer(minLength: 0)
            Button(Lang.t("rescue.enter")) {
                library.exitReadOnlyToRescue()
            }
            .font(.system(size: f12, weight: .semibold))
            .foregroundStyle(T.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readonlyBannerRow: some View {
        readonlyBannerContent
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20,
                                      bottom: 6, trailing: 20))
    }

    /// 顶部渐变罩：页面底色自上而下渐隐（纯色渐变、
    /// 无材质色差、无硬下边），罩住悬浮页眉下方穿行
    /// 的列表内容与状态栏区——用户要的「渐变模糊」
    /// 观感由胶囊自身玻璃 + 此罩共同承担。
    /// 紧凑进度：scrollY/30（Web 口径）；纯函数单
    /// 源 HomeHeaderMath（fix_home_header_vanish：
    /// 硬不变量与逐档期望见其定义处）。
    private var compactP: CGFloat {
        HomeHeaderMath.compactP(
            forOffset: nav.scrollOffset)
    }

    // 页眉（Web 口径）：左侧 72 头像即标题区（点进设置，
    // 无大文本标题）+ 右侧 66 高两态搜索胶囊；滚动紧凑
    // 时头像渐缩淡出、搜索隐藏、中央出现「此刻」胶囊。
    private var header: some View {
        ZStack {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    resignSearch()
                    nav.dest = .settings
                } label: {
                    AvatarView(size: 72)
                }
                // 头像淡出口径（Web 真值）：区间内只降
                // 至 0.7 + 上移 4，进度满才整隐——此前
                // 全程淡没与小标题浮现叠加成整块顶栏
                // 被「换掉」的硬切感。
                .scaleEffect(1 - 0.45 * compactP,
                             anchor: .leading)
                .offset(y: -4 * compactP)
                .opacity(compactP >= 1
                         ? 0 : 1 - 0.3 * compactP)
                // 命中阈值对齐 Web（AUD-A-04）：
                // 头像/搜索在 p<1 全程可点、紧凑
                // 胶囊 p≥1 接管——旧阈值 0.5 令
                // p∈[0.5,1) 三件皆不可点成死区；
                // Sanitizer 命中门带同步改判 30
                // （两处同值联动，见彼处注）。
                .allowsHitTesting(compactP < 1)
                Spacer()
                searchCapsule
                    .opacity(1 - compactP)
                    .allowsHitTesting(compactP < 1)
                    // 搜索展开/收起交叉淡入（M5）：动
                    // 画值 = 焦点派生展开态（单一真相）。
                    .animation(.easeInOut(duration: 0.2),
                               value: searchFocused)
            }
            // 「此刻」小标题（Web 真值）：进度满才出现
            // （Web 为 visibility 阈值切换），呈现加
            // 180ms 淡入（系统惯例）；此前全程半透明
            // 淡入，玻璃胶囊半透态最显「脏」，是硬切
            // 感知的落点。
            Button {
                resignSearch()
                nav.dest = .settings
            } label: {
                CompactTitle(text: Lang.t("app.title"))
            }
            // 纵向顶对齐（C-A2）：Web 胶囊 fixed top =
            // safe+7 与头像行顶同线；原先在 82 高页眉
            // 框内双轴居中、低约 21–25pt。
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(compactP >= 1 ? 1 : 0)
            .allowsHitTesting(compactP >= 1)
            .animation(.easeOut(duration: 0.18),
                       value: compactP >= 1)
        }
        // ≥1280 页眉同轴（C-A4，Web W-4 定案）：横内
        // 距 = (W−1240)/2 与网格容器边框盒同轴；未满
        // 或未量测时 20（1280 时恰 20、无缝衔接）。
        .padding(.horizontal, nav.homeW >= 1280
            ? (nav.homeW - 1240) / 2 : 20)
        .padding(.top, 7)
        .frame(height: 82)
    }

    /// 搜索胶囊二态（展开 ⟺ 搜索字段持焦，单一真
    /// 相派生）：展开态 = Web .glass-search-panel
    /// （overlay 档、高 66、padding 0/14、gap 8、
    /// 图标随正文色）；回车经 onSubmit 辞焦收起、
    /// 查询词保留续滤（Web onblur 同口径）；清除
    /// 钮为原生增强（清词 + 辞焦同收）。
    /// 结构（fix_search_tap_dead 根治）：常驻层
    /// （字段恒在层级）+ 触发层（收起态真 Button
    /// 覆盖）——分支条件不得是焦点本身：点按同
    /// 事务置焦并条件插入字段时，焦点请求因目标
    /// 缺席被吞、FocusState 回滚、分支随之塌回，
    /// 点按净效果为零（0.9.56 真机实报；与标题
    /// 胶囊 0.9.54 已 proven 的同型故障同构，其
    /// 根治同为字段常驻）。常驻层字段宽由焦点派
    /// 生（0↔140），层命中与焦点同源（收起不可
    /// 命中、展开才可命中）。
    private var searchCapsule: some View {
        ZStack(alignment: .leading) {
            // 常驻层（展开面）：字段恒在层级，置焦
            // 请求永远有活目标。
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: f15, weight: .medium))
                    .foregroundStyle(T.textMain)
                    .padding(.trailing, 8)
                TextField(Lang.t("search.placeholder"),
                          text: Binding(
                    get: { nav.query },
                    set: { nav.query = $0
                           library.search($0) }))
                    .font(.system(size: f15))
                    .frame(width: searchFocused ? 140 : 0,
                           height: 40)
                    .focused($searchFocused)
                    .onSubmit {
                        nav.searchCloseSrc = "submit"
                        searchFocused = false
                    }
                    .accessibilityHidden(!searchFocused)
                if !nav.query.isEmpty {
                    Button {
                        nav.query = ""
                        library.search("")
                        nav.searchCloseSrc = "clear"
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .overlayCard(radius: Radius.pill)
            .opacity(searchFocused ? 1 : 0)
            .allowsHitTesting(searchFocused)
            // 触发层（收起面）：点按走具名入口
            // activateSearch（手指与驱动共用同一
            // 闭包），字段不在此分支内。
            if !searchFocused {
                Button {
                    activateSearch()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: f17, weight: .medium))
                        Text(Lang.t("search.trigger"))
                            .font(.system(size: groupFontSize))
                            .tracking(-0.1)
                            .foregroundStyle(T.glassLabel)
                    }
                    .foregroundStyle(T.textSecondary)
                    .padding(.horizontal, 18)
                    .frame(height: 66)
                    .glassControl(radius: Radius.pill)
                }
                .buttonStyle(CardPressStyle())
                .transition(.opacity)
            }
        }
    }

    /// 组内子列（先图后文）：>2 折叠——首卡 meta 带
    /// 「▼ 展开 N 条」、展开后末卡带「▲ 收起」（Web 口径）。
    /// 子列折叠派生单点（fix_home_row_registry）：
    /// shown/ folded 的唯一出处——List 子列、网
    /// 格子列与行注册对账（shownRows）三方同
    /// 消费，杜绝「渲染一套、注册一套」的分叉
    /// （旧制注册随行视图走、与折叠派生无关，
    /// 是行面与模型脱钩的一半根源）。
    private func shownInSublist(
        group: MemoGroup, kind: String,
        memos: [MemoItem]
    ) -> (shown: [MemoItem], folded: Bool) {
        let key = "\(group.id)-\(kind)"
        let expanded = nav.expandedKeys.contains(key)
        let folded = memos.count > 2 && !expanded
        return (folded ? Array(memos.prefix(1))
            : memos, folded)
    }

    /// 呈现行集：与 body 渲染逐项同序同集（组
    /// 序 → 组内图子列 → 文子列，折叠经
    /// shownInSublist 同点收窄）；注册对账的唯
    /// 一真值源。
    private var shownRows: [(memo: MemoItem,
                             isImage: Bool,
                             form: String)] {
        let form = nav.homeWide ? "grid" : "list"
        var out: [(MemoItem, Bool, String)] = []
        for group in groups {
            for m in shownInSublist(
                group: group, kind: "img",
                memos: group.images).shown {
                out.append((m, true, form))
            }
            for m in shownInSublist(
                group: group, kind: "txt",
                memos: group.texts).shown {
                out.append((m, false, form))
            }
        }
        return out
    }

    /// 对账签名：呈现行集的 id/形态/判图串——
    /// 集变、形态切换（宽窄）、判图迁移（图↔
    /// 文子列）任一发生即变；标题/置顶/封面变
    /// 化不入签名（状态闭包现查模型，不靠重注
    /// 册保鲜）。
    private var rowSyncSignature: String {
        shownRows.map {
            "\($0.memo.id)|\($0.form)|"
                + "\($0.isImage ? 1 : 0)"
        }.joined(separator: ",")
    }

    /// 行面状态/动作的模型现查（注册条目闭包
    /// 恒经此读活值，不吃注册时刻的备忘快照）。
    private func liveMemo(_ id: String)
        -> MemoItem? {
        library.memos.first { $0.id == id }
    }

    /// home.row 条目构造单点（fix_home_row_
    /// registry）：动作与左滑菜单/网格菜单同
    /// 体（resignSearch + 模型单点、open 经
    /// openMemo 漏斗），与旧锚点条目逐项等
    /// 价，唯状态/动作改经 liveMemo 现查、
    /// frameInWindow 仍读行帧通道。
    private func makeRowEntry(
        _ row: (memo: MemoItem, isImage: Bool,
                form: String)
    ) -> UITestSurfaceEntry {
        let id = row.memo.id
        var state: [String: () -> String] = [
            "form": { row.form },
            "isImage": {
                liveMemo(id).map {
                    $0.hasImageShape(
                        names: library.attachmentNames,
                        types: library.attachmentTypes)
                        ? "true" : "false"
                } ?? ""
            },
            "pinned": {
                liveMemo(id).map {
                    $0.pinned ? "true" : "false"
                } ?? ""
            },
            "title": { liveMemo(id)?.title ?? "" },
            "coverFileId": {
                liveMemo(id).map {
                    $0.coverPair(
                        names: library.attachmentNames,
                        types: library.attachmentTypes).0
                        ?? ""
                } ?? ""
            },
        ]
        if row.form == "list" {
            // 行卡圆角派生回读（HOM-17）：与旧
            // 列表行条目同键同值（Radius.cardL）。
            state["radius"] = { "\(Radius.cardL)" }
        }
        return UITestSurfaceEntry(
            id: "home.row", kind: "row",
            instance: id,
            frameInWindow: {
                rowFrameStore.frames[id]
            },
            actions: [
                "pin": { _ in
                    guard let m = liveMemo(id)
                    else { return }
                    resignSearch()
                    library.togglePin(m)
                },
                "delete": { _ in
                    guard let m = liveMemo(id)
                    else { return }
                    resignSearch()
                    library.softRemove(m)
                },
                "open": { _ in
                    guard let m = liveMemo(id)
                    else { return }
                    openMemo(m)
                },
            ],
            state: state)
    }

    /// 单行注销（注册与帧同点收口）：条目摘除
    /// 的同一笔把行帧清掉——帧不再有独立于注
    /// 册面的寿命（旧制帧永不清是幽灵行带帧
    /// 污染 home_geometry 量测的直接通道）。
    private func unregisterRow(_ id: String) {
        if let owner =
            rowRegistryStore.owners[id] {
            UITestRegistry.shared.unregister(
                owner: owner)
            rowRegistryStore.owners[id] = nil
        }
        rowFrameStore.frames[id] = nil
    }

    /// 注册对账（fix_home_row_registry 单点）：
    /// 管辖集与呈现行集对齐——集外注销（连
    /// 帧）、集内以稳定 owner 重注册（条目闭
    /// 包保鲜）；增减非空记一行结果侧 Diag。
    private func syncRowRegistry() {
        let shown = shownRows
        let want = Set(shown.map { $0.memo.id })
        var added = 0
        var removed = 0
        for id in Array(rowRegistryStore
            .owners.keys) where !want.contains(id) {
            unregisterRow(id)
            removed += 1
        }
        for row in shown {
            if rowRegistryStore
                .owners[row.memo.id] == nil {
                rowRegistryStore
                    .owners[row.memo.id] = UUID()
                added += 1
            }
            UITestRegistry.shared.register(
                makeRowEntry(row),
                owner: rowRegistryStore
                    .owners[row.memo.id]!)
        }
        if added > 0 || removed > 0 {
            DiagLog.shared.log(.info,
                "APP home rows sync "
                + "+\(added) -\(removed) "
                + "n=\(shown.count)")
        }
    }

    /// 离场全注销（ListView 退出层级时行面不
    /// 留跨场残影）。
    private func clearRowRegistry() {
        for id in Array(rowRegistryStore
            .owners.keys) {
            unregisterRow(id)
        }
    }

    @ViewBuilder
    private func sublist(group: MemoGroup, kind: String,
                         memos: [MemoItem]) -> some View {
        let key = "\(group.id)-\(kind)"
        let (shown, folded) = shownInSublist(
            group: group, kind: kind, memos: memos)
        ForEach(shown) { memo in
            memoRow(memo,
                    isImage: kind == "img",
                    expandHint: folded && memo.id == shown.first?.id
                        ? (memos.count, {
                            nav.expandedKeys.insert(key)
                            DiagLog.shared.log(.info,
                                "APP row expand tap \(key)")
                        }) : nil,
                    collapseHint: !folded && memos.count > 2
                        && memo.id == shown.last?.id
                        ? { nav.expandedKeys.remove(key)
                            DiagLog.shared.log(.info,
                                "APP row collapse tap \(key)") }
                        : nil)
        }
    }

    private var undoToast: some View {
        // 全宽条（C-A1，Web .backup-toast）：左右 16、
        // 底 = safe + 16（根 ZStack 底即 safe 底）、
        // radius 28 overlay 档、padding 14/16、gap 10、
        // 删除图标 19、文字 14/500、撤销钮 14/600 带
        // padding 6/10。此前居中胶囊无图标为自创形态。
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: f19))
                .foregroundStyle(T.textMain)
            Text(Lang.t("list.deleted_toast"))
                .font(.system(size: groupFontSize,
                              weight: .medium))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
            Button(Lang.t("action.undo")) {
                library.undoDeletion()
            }
                .font(.system(size: groupFontSize,
                              weight: .semibold))
                .foregroundStyle(T.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .buttonStyle(CardPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlayCard(radius: Radius.panel)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        // 进场（Web 口径）：220ms 弹簧上滑 + 淡入。
        .transition(.move(edge: .bottom)
            .combined(with: .opacity))
    }

    // ── 首页宽屏网格（Web 口径）──────────────────
    /// 网格形态：ScrollView + 组块纵排（3/4 列、gap
    /// 14、容器上限 1240 居中、左右 24；框序 = 内距
    /// 先于框——1240 含内距、内容宽 1192，与 Web
    /// border-box 同账，框缘与页眉收轴同为
    /// (W−1240)/2，审计 L-1）；方卡 aspect 1/1、
    /// radius 26；折叠组首卡叠卡呈现。左滑不可用，
    /// 长按菜单补删除/置顶。
    ///
    /// 结构定案（fix_home_grid_landscape）：全跨
    /// 元素（横幅/公告/组标题/空状态）一律在
    /// LazyVGrid **之外**的纵排里、组内卡片各自
    /// 成网格连续流排。缘由：Web .section-header
    /// 以 grid-column: 1 / -1 全跨（base.css:
    /// 390-401），而 SwiftUI 的跨列修饰 gridCell-
    /// Columns 是 eager Grid 的 API、LazyVGrid
    /// 无列跨越语义、修饰被静默忽略——旧结构把
    /// 标题放进网格并挂该修饰，0.9.58 真机上标
    /// 题退化为普通单元格：折叠组每组恰出「标
    /// 题+图+文」三件凑满一行、标题逐组对齐成
    /// 第一列、卡恒不满 3 列（1180 三列同病、
    /// 1366 四列更散）。纵排与 Web display:
    /// contents 的单网格流在组边界处等价（组头
    /// 在 Web 同样强制换行、卡不在组间混排）；
    /// 纵向间隙按单网格行距 14 逐段合成（组头
    /// 底 −6 与段距 14 合成距首卡 8、组头顶距
    /// = 段距 14 + 头内顶距 8 = 22，与 Web 行
    /// 距 + padding-top 同账）。
    private var gridHome: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶占位与窄屏同账不同值：不变量 =
                // 首卡顶 = 头像底 79 + Web 间距 56
                // = 135；窄屏有首行 top inset 3 故
                // 占位 132，网格无行 inset 故占位
                // 135（见 fix_home_search_layout）。
                // 纯占位行（旧兼作基线探针的量测已
                // 随基线制退役移交 HomeScrollProbe，
                // fix_home_regressions_0957）。
                Color.clear
                    .frame(height: 135)
                VStack(spacing: 14) {
                    if library.isReadOnly {
                        readonlyBannerContent
                    }
                    if !library.notice.isEmpty {
                        Text(library.notice)
                            .font(.system(size: f12))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                    }
                    if !library.loadFailed && !library.isReadOnly {
                        LazyVGrid(columns: gridColumns,
                                  spacing: 14) {
                            newCardSquare
                        }
                    }
                    ForEach(groups) { group in
                        VStack(spacing: 14) {
                            // 网格组头（Web .container
                            // .section-header：13/600、
                            // 色 --glass-label-color、
                            // letter-spacing .02em、
                            // padding 8/2/0、margin-
                            // bottom −6 → 与段距 14 合
                            // 成距首卡 8，base.css:
                            // 390-401）。此前色用 text-
                            // Secondary、无负底距 →
                            // 合成 14（B9 登记项）。
                            Text(group.title)
                                .font(.system(size: f13, weight: .semibold))
                                .foregroundStyle(T.glassLabel)
                                .tracking(0.3)
                                // 大写呈现对齐 Web 网格
                                // 组头 text-transform
                                // （AUD-A-05；与窄屏
                                // groupHeader 同口径）。
                                .textCase(.uppercase)
                                .frame(maxWidth: .infinity,
                                       alignment: .leading)
                                .padding(.top, 8)
                                .padding(.leading, 2)
                                .padding(.bottom, -6)
                            LazyVGrid(columns: gridColumns,
                                      spacing: 14) {
                                gridSublist(group: group,
                                            kind: "img",
                                            memos: group.images)
                                gridSublist(group: group,
                                            kind: "txt",
                                            memos: group.texts)
                            }
                        }
                    }
                    if visibleMemos.isEmpty
                        && library.didLoad {
                        gridEmpty
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 1240)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14),
              count: nav.homeCols)
    }

    @ViewBuilder
    private func gridSublist(group: MemoGroup, kind: String,
                             memos: [MemoItem]) -> some View {
        let key = "\(group.id)-\(kind)"
        let (shown, folded) = shownInSublist(
            group: group, kind: kind, memos: memos)
        ForEach(shown) { memo in
            squareCard(
                memo,
                isImage: kind == "img",
                stacked: folded,
                total: memos.count,
                expand: folded
                    ? { nav.expandedKeys.insert(key)
                        DiagLog.shared.log(.info,
                            "APP row expand tap \(key)") } : nil,
                collapse: (!folded && memos.count > 2
                    && memo.id == shown.last?.id)
                    ? { nav.expandedKeys.remove(key)
                        DiagLog.shared.log(.info,
                            "APP row collapse tap \(key)") } : nil)
        }
    }

    private var gridEmpty: some View {
        // 三态（H3）：与窄屏 emptyRow 同构成——加载
        // 失败 / 搜索零结果 / 空库。此前只有两态：
        // 宽屏搜索无结果（visibleMemos 空）时误显
        // 空库态、动作还是「新建备忘」；搜索态标题
        // 含 query、动作应为「清除搜索」。度量沿批
        // A 已核的网格口径（钮 22/9 + top 10、纵
        // 56），只补状态不改度量。
        let state: (icon: String, title: String,
                    desc: String, action: String,
                    run: () -> Void) = {
            if library.loadFailed {
                return ("exclamationmark.triangle",
                        Lang.t("empty.load_error_title"),
                        Lang.t("empty.load_error_sub"),
                        Lang.t("empty.retry"),
                        { library.retryLoad() })
            }
            if library.searchHits != nil {
                return ("magnifyingglass",
                        Lang.tf("empty.search_title",
                                ["q": nav.query]),
                        Lang.t("empty.search_sub"),
                        Lang.t("empty.clear_search"), {
                            nav.query = ""
                            library.search("")
                        })
            }
            return ("note.text",
                    Lang.t("empty.library_title"),
                    Lang.t("list.empty_tip"),
                    Lang.t("empty.new_memo"), {
                        createAndOpen()
                    })
        }()
        return VStack(spacing: 8) {
            Image(systemName: state.icon)
                .font(.system(size: f44))
                .foregroundStyle(
                    T.textSecondary.opacity(0.55))
            Text(state.title)
                .font(.system(size: f16, weight: .semibold))
                .foregroundStyle(T.textMain)
            Text(state.desc)
                .font(.system(size: f13))
                .lineSpacing(7)
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: 280)
                .multilineTextAlignment(.center)
            Button {
                state.run()
            } label: {
                Text(state.action)
                    .font(.system(size: groupFontSize,
                                  weight: .semibold))
                    .foregroundStyle(T.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(T.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.vertical, 56)
    }

    private var newCardSquare: some View {
        Button {
            createAndOpen()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(Lang.t("list.new_note"))
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textSecondary)
                Text("\(Lang.t("list.now"))\u{00A0}\u{00A0}"
                     + "\(Lang.t("list.new_note_sub"))")
                    .font(.system(size: f12))
                    .foregroundStyle(T.glassLabel)
                Spacer(minLength: 0)
                if let w = weather.now {
                    // 天气底部整行（C-A5，Web 宽屏规则）：
                    // 温度左、城况右、同行两端分布；原
                    // 右下两行堆叠为自创形态。
                    HStack {
                        Text("\(w.temp)°")
                            .font(.system(size: f16, weight: .semibold))
                            .foregroundStyle(T.textMain)
                        Spacer()
                        Text([w.city, w.text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " "))
                            .font(.system(size: f12))
                            .foregroundStyle(T.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: .topLeading)
            .glassCard(radius: Radius.grid)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(CardPressStyle())
    }

    /// 方卡（Web 宽屏口径）：aspect 1/1、radius 26、
    /// 内边距 14；折叠组首卡带两层幽灵叠卡、整卡点按
    /// 展开；长按菜单补网格无左滑的删除/置顶。
    private func squareCard(
        _ memo: MemoItem, isImage: Bool,
        stacked: Bool, total: Int,
        expand: (() -> Void)?, collapse: (() -> Void)?
    ) -> some View {
        ZStack {
            if stacked {
                RoundedRectangle(cornerRadius: Radius.grid)
                    .fill(T.contentBg)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.grid)
                            .stroke(T.borderSoft,
                                    lineWidth: 0.5)
                    }
                    .scaleEffect(0.94)
                    .offset(y: 7)
                    .opacity(0.68)
                RoundedRectangle(cornerRadius: Radius.grid)
                    .fill(T.contentBg)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.grid)
                            .stroke(T.borderSoft,
                                    lineWidth: 0.5)
                    }
                    .scaleEffect(0.97)
                    .offset(y: 4)
                    .opacity(0.86)
            }
            Group {
                // 图文分类由 gridSublist 的 kind 下传
                // （组分区同一次判定），卡内不再重探。
                if isImage {
                    squareImageCard(memo, expand: expand,
                                    collapse: collapse,
                                    total: total)
                } else {
                    squareTextCard(memo, total: total,
                                   expand: expand,
                                   collapse: collapse)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture {
                if let expand {
                    expand()
                } else {
                    openMemo(memo)
                }
            }
            .contextMenu {
                Button {
                    openMemo(memo)
                } label: {
                    Label(Lang.t("list.open"),
                          systemImage: "pencil")
                }
                Button {
                    resignSearch()
                    library.togglePin(memo)
                } label: {
                    Label(memo.pinned
                          ? Lang.t("action.unpin")
                          : Lang.t("action.pin"),
                          systemImage: memo.pinned
                            ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    // 网格菜单同辞焦（AUD-A-07）。
                    resignSearch()
                    library.softRemove(memo)
                } label: {
                    Label(Lang.t("action.delete"),
                          systemImage: "trash")
                }
            }
        }
        // 行帧通道（U5）：只报帧；home.row 注
        // 册已收口 syncRowRegistry 对账单点
        // （fix_home_row_registry），行视图不
        // 再自带注册锚点。
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    rowFrameStore.frames[memo.id] =
                        geo.frame(in: .global)
                }
                .onChange(of: geo.frame(
                    in: .global)) { f in
                    rowFrameStore.frames[memo.id] = f
                }
        })
    }

    private func squareTextCard(
        _ memo: MemoItem, total: Int,
        expand: (() -> Void)?, collapse: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                if memo.pinned {
                    Circle()
                        .fill(T.warning)
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                }
                Text(memo.title.isEmpty
                     ? Lang.t("list.untitled") : memo.title)
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineLimit(3)
                    .lineSpacing(5.6)
            }
            squareTags(memo, small: false)
            Spacer(minLength: 0)
            // meta 行：文案 + 折叠/收起药丸同行（钮
            // 在行右端，与窄屏 metaRow 同构）。
            HStack(alignment: .bottom, spacing: 6) {
                Text("\(memo.ago)  \(memo.summary(isImage: false))")
                    .font(.system(size: f12))
                    .foregroundStyle(T.glassLabel)
                    .lineLimit(3)
                    .lineSpacing(5.4)
                if expand != nil || collapse != nil {
                    Spacer(minLength: 8)
                    squareFoldPill(expand: expand,
                                   collapse: collapse,
                                   total: total)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: .topLeading)
        .glassCard(radius: Radius.grid)
    }

    private func squareImageCard(
        _ memo: MemoItem, expand: (() -> Void)?,
        collapse: (() -> Void)?, total: Int
    ) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let pair = memo.coverPair(
                    names: library.attachmentNames,
                    types: library.attachmentTypes)
                ItemImageView(
                    fileId: pair.0,
                    urlString: pair.1,
                    library: library)
                    .frame(width: geo.size.width,
                           height: geo.size.height)
            }
            .frame(maxHeight: .infinity)
            // 图区子面按位取角（贴顶只圆上角、与文
            // 区交界直角，内角规矩）。
            .clipShape(CornerRect(tl: Radius.grid,
                                  tr: Radius.grid))
            VStack(alignment: .leading, spacing: 3) {
                Text(memo.title.isEmpty
                     ? Lang.t("list.untitled") : memo.title)
                    .font(.system(size: f13, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                squareTags(memo, small: true)
                // meta 行：文案 + 折叠药丸同行（小差
                // 9，此前收起钮是 meta 行外的独立行
                // 纯文字、纵位差一行）。药丸与文本
                // 方卡同走 squareFoldPill 单点（AUD-
                // A-06：此前图文卡只有收起支、内联
                // 自绘同视觉一份，折叠态缺展开药丸
                // 「展开 · 共 N 条」——Web 两卡渲染
                // 同一 MemoRow、药丸无分类差）。
                HStack(spacing: 6) {
                    Text("\(memo.ago) · \(memo.summary(isImage: true))")
                        .font(.system(size: f12))
                        .foregroundStyle(T.glassLabel)
                        .lineLimit(1)
                    if expand != nil || collapse != nil {
                        Spacer(minLength: 8)
                        squareFoldPill(expand: expand,
                                       collapse: collapse,
                                       total: total)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 文区高改内容驱动下限（DT 韧性类 B，
            // impl_dt_home_resilience R-2）：默认
            // 档内容 ≈76.5（题 17 + 标签 18 + meta
            // 15.6 + 间距 6 + 内距 20）< 78、min-
            // Height 托底恒 78 逐值不变；AX 档题/
            // 标签/meta 随字生长、文区随之长高，
            // 图区（maxHeight .infinity）相应让位
            // ——旧定高 78 在 AX5 内容 ≈175 必溢
            // 出裁字。整卡 aspect 1/1 与列表交界
            // 账（22/16）均不经此帧、不受影响。
            .frame(minHeight: 78)
        }
        .glassCard(radius: Radius.grid)
        .clipShape(RoundedRectangle(cornerRadius: Radius.grid))
    }

    /// 方卡标签行（Web 口径）：只显前 2 个 + 多余计数；
    /// 文本卡 11 号、图文卡 10 号。
    private func squareTags(_ memo: MemoItem,
                            small: Bool) -> some View {
        HStack(spacing: small ? 4 : 6) {
            ForEach(memo.tags.prefix(2), id: \.self) { tag in
                // chip 本体与行卡同 .glass-tag 口
                // 径（accent 蓝字 + control 底边）；
                // 高：方卡 font 11 / line-height 20、
                // 图文方卡 font 10 / line-height 18
                // （base.css:474-495、546-556）。
                // 此前灰字无边、高 ≈18.2/14（B2）。
                // 高以 minHeight 承载（DT 韧性类
                // B，impl_dt_home_resilience R-1）：
                // Web 的 20/18 是行高本体——默认
                // 档文字行高小于此值、minHeight
                // 托底恒 20/18 逐值不变；AX 档随
                // 字生长，不再被 glassControl
                // 纵向裁字（旧定高在 AX5 行高
                // ≈42/47 下必裁）。
                Text("#\(tag)")
                    .font(.system(size: small ? f10 : f11))
                    .foregroundStyle(T.glassLabelAccent)
                    .lineLimit(1)
                    .padding(.horizontal, small ? 6 : 7)
                    .frame(minHeight: small ? 18 : 20)
                    .glassControl(radius: Radius.pill)
            }
            if memo.tags.count > 2 {
                Text("+\(memo.tags.count - 2)")
                    .font(.system(size: small ? f10 : f11))
                    .foregroundStyle(T.glassLabelAccent)
                    .lineLimit(1)
                    .padding(.horizontal, small ? 6 : 7)
                    .frame(minHeight: small ? 18 : 20)
                    .glassControl(radius: Radius.pill)
            }
        }
    }

    /// 方卡折叠/收起钮（小差 9）：与窄屏同为 meta
    /// 行内 .expand-btn 玻璃药丸（11 号、padding
    /// 4/10、radius 14、glass-label 色）——Web 网
    /// 格与窄屏渲染同一 MemoRow 组件、同一钮；
    /// 此前原生为独立行 12 号 accent 纯文字（C-A6
    /// 当时以「网格无同名对应物」排除，经查排除
    /// 前提不成立）。
    @ViewBuilder
    private func squareFoldPill(
        expand: (() -> Void)?, collapse: (() -> Void)?,
        total: Int
    ) -> some View {
        if let expand {
            Button(Lang.tf("list.expand_n",
                           ["n": "\(total)"])) { expand() }
                .font(.system(size: f11))
                .foregroundStyle(T.glassLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassControl(radius: Radius.controlS)
                .buttonStyle(.plain)
        } else if let collapse {
            Button(Lang.t("list.collapse")) { collapse() }
                .font(.system(size: f11))
                .foregroundStyle(T.glassLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassControl(radius: Radius.controlS)
                .buttonStyle(.plain)
        }
    }

    private var newCardRow: some View {
        Button {
            createAndOpen()
        } label: {
            // 横距合成（二轮微差）：左列与天气文案的
            // 最小间距 = spacing 6 ×2（Spacer 两侧）
            // + 天气块 leading 12 = 24，与 Web
            // .list-item gap 12 + 天气 padding-left
            // 12 同值；此前 spacing 10 合成 ≈32。
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Lang.t("list.new_note"))
                        .font(.system(size: f16, weight: .semibold))
                        .foregroundStyle(T.textSecondary)
                    Text("\(Lang.t("list.now"))\u{00A0}\u{00A0}"
                         + "\(Lang.t("list.new_note_sub"))")
                        .font(.system(size: f12))
                        // 副行在 .item-meta 内，同 H4
                        // 走 glass-label 色。
                        .foregroundStyle(T.glassLabel)
                }
                Spacer(minLength: 0)
                // 天气块（Web 口径）：有数才渲染、缺数
                // 整块不出现（无占位无报错）。
                if let w = weather.now {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(w.temp)°")
                            .font(.system(size: f16, weight: .semibold))
                            .tracking(-0.5)
                            .foregroundStyle(T.textMain)
                        Text([w.city, w.text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " "))
                            .font(.system(size: f12))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.leading, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassCard()
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16,
                                  bottom: 3, trailing: 16))
    }

    private func groupHeader(_ title: String,
                             topInset: CGFloat) -> some View {
        Text(title)
            .font(.system(size: groupFontSize,
                          weight: .semibold))
            .foregroundStyle(T.textSecondary)
            // 字距与大写（Web .section-header：
            // letter-spacing 0.3 + text-transform
            // uppercase，editor.css:139-146；设置页
            // SectionHeader 已同口径，首页组头此前
            // 漏设——B6 登记项）。
            .tracking(0.3)
            .textCase(.uppercase)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // 组间合成距对齐 Web 28/6：Web = 前组
            // .list-group margin-bottom 24 + 组头
            // padding-top 4（:first-child——组头恒
            // 为组包裹首子）→ 文字上 28；文字下 =
            // padding-bottom 6。原生合成 = 前卡
            // bottom inset 3 + 本行 top 25 = 28；
            // 本行 bottom 3 + 首卡 top inset 3 =
            // 6。此前 24/6 合成 27/9（B6 登记项）。
            // top 自 AUD-A-08 起形参化：恒经
            // HomeHeaderMath.firstGroupTopInset
            // 按紧邻行 bottom 反推（卡邻居 3 →
            // 25 本账不变；首组头紧邻随横幅/
            // notice/loadFailed 变、间隔恒 28，
            // fix_home_header_gap_adaptive）。
            .listRowInsets(EdgeInsets(top: topInset, leading: 20,
                                      bottom: 3, trailing: 16))
    }

    @ViewBuilder
    private func memoRow(
        _ memo: MemoItem,
        isImage: Bool,
        expandHint: (Int, () -> Void)? = nil,
        collapseHint: (() -> Void)? = nil
    ) -> some View {
        // 整卡点按走手势而非 Button 包裹：折叠提示钮在
        // meta 行内需要独立命中，Button 嵌套会吞掉它。
        // 图文分类由 sublist 的 kind 下传（与组分区同
        // 一次判定、同谓词同清单），行内不再重探
        // hasImageShape（每行省一趟块扫描/封面探针）。
        Group {
            if isImage {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        let pair = memo.coverPair(
                            names: library.attachmentNames,
                            types: library.attachmentTypes)
                        ItemImageView(
                            fileId: pair.0,
                            urlString: pair.1,
                            library: library)
                            .frame(width: geo.size.width,
                                   height: geo.size.height)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()
                    VStack(alignment: .leading, spacing: 3) {
                        titleRow(memo, size: 15,
                                 isImage: true)
                        metaRow(memo, isImage: true,
                                expandHint: expandHint,
                                collapseHint: collapseHint)
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .glassCard()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    titleRow(memo, size: 16)
                    metaRow(memo, isImage: false,
                            expandHint: expandHint,
                            collapseHint: collapseHint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .glassCard()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 折叠态整卡点按 = 展开（H2，Web
            // render_sub 折叠分支：首卡 on_open 被
            // 替换为展开动作）；展开态/普通卡才打开
            // 编辑器。与网格 squareCard 同语义；meta
            // 行药丸是另一条展开路径，两边并存。
            if let hint = expandHint {
                hint.1()
            } else {
                openMemo(memo)
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 3, leading: 16,
                                  bottom: 3, trailing: 16))
        .swipeActions(edge: .trailing,
                      allowsFullSwipe: false) {
            Button(role: .destructive) {
                // 列表动作先辞焦（AUD-A-07：搜索
                // 激活态下左滑删除/置顶后焦点与键
                // 盘残留，与点按打开的辞焦口径齐）。
                resignSearch()
                library.softRemove(memo)
            } label: {
                Label(Lang.t("action.delete"),
                      systemImage: "trash")
            }
            .tint(T.danger)
            Button {
                resignSearch()
                library.togglePin(memo)
            } label: {
                Label(memo.pinned
                      ? Lang.t("action.unpin")
                      : Lang.t("action.pin"),
                      systemImage: memo.pinned
                        ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        // 行帧通道（U5）：window 坐标帧回报（纯存
        // 储盒、不触发重演算），供 home.row 面与
        // P4 探针量测。
        .background(GeometryReader { geo in
            Color.clear
                .onAppear {
                    rowFrameStore.frames[memo.id] =
                        geo.frame(in: .global)
                }
                .onChange(of: geo.frame(
                    in: .global)) { f in
                    rowFrameStore.frames[memo.id] = f
                }
        })
        // home.row 注册已收口 syncRowRegistry
        // 对账单点（fix_home_row_registry）：
        // 条目由对账按呈现行集构造（makeRow-
        // Entry，动作与左滑菜单同体、状态现
        // 查），行视图只留上方帧通道、不再自
        // 带注册锚点。
    }

    private func titleRow(_ memo: MemoItem,
                          size: CGFloat,
                          isImage: Bool = false) -> some View {
        // 标题上限口径（审计二轮更正 C-A7）：Web
        // .item-title-text 的 max-width 60% 以其包含
        // 块 .item-title-main 为基数；title-main 与
        // .item-tag-list 各 flex:1（basis 0）——有
        // 标签时两区各占半行，文本卡标题上限 =
        // 60% × 半行 ≈ 30% 行宽；无标签时 tag-list
        // 不渲染、main 独占整行、上限 60% 行宽。
        // 图文卡 .img-card-title-text 无 max-width，
        // 占满 title-main 全宽。此前恒按 0.6×整行：
        // 有标签时长标题多显约一倍、图文卡截断偏早。
        GeometryReader { geo in
            let w = geo.size.width
            let hasTags = !memo.tags.isEmpty
            // title-main 宽：有标签半行、无标签整行。
            let mainW = hasTags ? w * 0.5 : w
            let titleCap = isImage ? mainW : mainW * 0.6
            HStack(spacing: 6) {
                if memo.pinned {
                    Circle()
                        .fill(T.warning)
                        .frame(width: 6, height: 6)
                }
                Text(memo.title.isEmpty
                     ? Lang.t("list.untitled") : memo.title)
                    .font(.system(size: size * titleFontScale,
                                  weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                    .frame(maxWidth: titleCap,
                           alignment: .leading)
                Spacer(minLength: 4)
                if hasTags {
                    // 标签区：flex:1 半行封顶、右对
                    // 齐；chip 间距 4（.item-tag-list
                    // gap，二轮微差）。
                    HStack(spacing: 4) {
                        ForEach(memo.tags.prefix(3),
                                id: \.self) { tag in
                            // chip 本体（Web .glass-
                            // tag + 行卡内联度量：accent
                            // 蓝字、control 底 + 边、
                            // font 10 / line-height 18 /
                            // padding 0/5，base.css:354-
                            // 358、list.rs:1164-1172）。
                            // 此前灰字、无边、高 ≈16
                            // （B2 登记项）。高以 min-
                            // Height 18 承载（DT 韧性
                            // 类 B，impl_dt_home_resi-
                            // lience R-1）：18 是 Web
                            // 行高本体、默认档托底逐值
                            // 不变，AX 档随字生长不裁；
                            // 行盒 20×titleFontScale
                            // 同步缩放、恒容得下。
                            Text("#\(tag)")
                                .font(.system(size: f10))
                                .foregroundStyle(
                                    T.glassLabelAccent)
                                .lineLimit(1)
                                .padding(.horizontal, 5)
                                .frame(minHeight: 18)
                                .glassControl(radius: Radius.pill)
                        }
                    }
                    .frame(maxWidth: w * 0.5,
                           alignment: .trailing)
                    .clipped()
                }
            }
            // 行高随标题缩放同步（二轮微差）：标题字
            // 号经 titleFontScale 随 Dynamic Type 放
            // 大，行盒同步 20×scale，防大字号档挤压。
            .frame(height: 20 * titleFontScale)
        }
        .frame(height: 20 * titleFontScale)
    }

    /// meta 行（Web 口径）：文本卡「{ago}␣␣{摘要}」双空
    /// 格同段截断；图文卡「{ago} · {摘要}」；折叠提示附尾。
    private func metaRow(
        _ memo: MemoItem, isImage: Bool,
        expandHint: (Int, () -> Void)?,
        collapseHint: (() -> Void)?
    ) -> some View {
        HStack(spacing: 6) {
            Text(isImage
                 ? "\(memo.ago) · \(memo.summary(isImage: true))"
                 : "\(memo.ago)  \(memo.summary(isImage: false))")
                .lineLimit(1)
            if expandHint != nil || collapseHint != nil {
                Spacer(minLength: 8)
            }
            // 展开/收起钮（C-A6，Web .expand-btn）：恒
            // 居 meta 行右端、glass-control 药丸（11 号、
            // padding 4/10、radius 14、glass-label 色）。
            if let hint = expandHint {
                Button(Lang.tf("list.expand_n",
                               ["n": "\(hint.0)"])) {
                    hint.1()
                }
                    .font(.system(size: f11))
                    .foregroundStyle(T.glassLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassControl(radius: Radius.controlS)
                    .buttonStyle(.plain)
            }
            if let collapse = collapseHint {
                Button(Lang.t("list.collapse")) { collapse() }
                    .font(.system(size: f11))
                    .foregroundStyle(T.glassLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassControl(radius: Radius.controlS)
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: metaFontSize))
        // meta 色（H4）：Web .item-meta 由 base.css
        // 后部组规则定为 --glass-label-color（覆盖
        // 同文件先行的 --text-secondary 声明，归档
        // 同构）——此前误用 T.textSecondary，深色下
        // 差最显（#98989D vs #D1D1D6）。
        .foregroundStyle(T.glassLabel)
    }

    /// 空状态三态（Web EmptyState 口径：44 图标 @55% +
    /// 标题 + 说明 + accent 胶囊动作钮）。
    @ViewBuilder
    private var emptyRow: some View {
        let state: (icon: String, title: String, desc: String,
                    action: String, run: () -> Void) = {
            if library.loadFailed {
                return ("exclamationmark.triangle",
                        Lang.t("empty.load_error_title"),
                        Lang.t("empty.load_error_sub"),
                        Lang.t("empty.retry"),
                        { library.retryLoad() })
            }
            if library.searchHits != nil {
                return ("magnifyingglass",
                        Lang.tf("empty.search_title",
                                ["q": nav.query]),
                        Lang.t("empty.search_sub"),
                        Lang.t("empty.clear_search"), {
                            nav.query = ""
                            library.search("")
                        })
            }
            return ("note.text",
                    Lang.t("empty.library_title"),
                    Lang.t("list.empty_tip"),
                    Lang.t("empty.new_memo"), {
                        createAndOpen()
                    })
        }()
        VStack(spacing: 8) {
            Image(systemName: state.icon)
                .font(.system(size: f44))
                .foregroundStyle(T.textSecondary.opacity(0.55))
            Text(state.title)
                .font(.system(size: f16, weight: .semibold))
                .foregroundStyle(T.textMain)
            Text(state.desc)
                .font(.system(size: f13))
                // 说明度量（Web .empty-state p：
                // 13 / line-height 1.55 / max-width
                // 280，editor.css:137；与 gridEmpty
                // 同值——B8 登记项，此前窄屏独缺）。
                .lineSpacing(7)
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: 280)
                .multilineTextAlignment(.center)
            Button(state.action) { state.run() }
                .font(.system(size: groupFontSize,
                              weight: .semibold))
                .foregroundStyle(T.onAccent)
                // 动作钮度量（Web：padding 9/22、
                // margin-top 10，editor.css:138；
                // 与 gridEmpty 同值，B8 登记项）。
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(T.accent, in: Capsule())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        // 纵内距 56（Web .empty-state padding
        // 56/24，editor.css:132；B8 登记项）。
        .padding(.vertical, 56)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        // 显式零 insets（同 C-A3 分隔行教训：
        // 未声明即继承系统默认 insets，纵 56
        // 的账面值被静默放大——fix_home_
        // card_spacing.md，F30-13 计数锁守）。
        .listRowInsets(EdgeInsets())
    }
}

// ── 子页骨架（Web 口径：左上玻璃返回圆钮 + 居中紧凑标题
// 胶囊 + 内容 81 顶距） ─────────────────────────────
struct CompactTitle: View {
    var text: String
    // 语义字体喂点（fix_dynamic_type_follow）：
    // headline = body 尺寸 + semibold 字重。
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17
    var body: some View {
        Text(text)
            // 单行不折（Web .page-title.compact 的
            // nowrap 口径）：长名横向溢出由外层居中承
            // 载。此前漏设，长文件名在胶囊内折成多行
            // ——用户实报的图片页标题异形（排查 #2 只
            // 对了「无截断」一半、漏了 nowrap 一半）。
            .lineLimit(1)
            .font(.system(size: f17, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(T.textMain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            // 材质档（Web .page-title.compact =
            // --glass-overlay，base.css:85-111）：
            // overlay 档（overlayCard），此前误用
            // glassCard 内容档（B4 登记项；各子页
            // 经 ChromeView 共用同一组件、Web 同
            // 为 overlay，一并对齐）。
            .overlayCard(radius: Radius.panelS)
    }
}

struct ChromeView<Content: View>: View {
    var title: String
    var onBack: () -> Void
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            content()
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: f17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: Radius.pill)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            CompactTitle(text: title)
                .padding(.top, 11)
        }
        .background(T.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SectionHeader: View {
    var text: String
    /// 顶距覆盖（默认 24 不变）：设置页首组与诊断页
    /// 「当天日志」组按 Web 内联口径改 4（批 E）。
    var topPad: CGFloat = 24
    /// 标题色覆盖（默认次级不变）：备份页节标题按
    /// C2 级联口径走 glass-label（批 E）。
    var tint: Color = T.textSecondary
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    var body: some View {
        Text(text)
            .font(.system(size: f14, weight: .semibold))
            .foregroundStyle(tint)
            .tracking(0.3)
            // 组头大写（S8）：Web .section-header 带
            // text-transform: uppercase——中文无字形
            // 变化、en-US 等语境才生效，系统呈现承接。
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, topPad)
            .padding(.bottom, 6)
    }
}

/// 备份页专用节标题（S3，Web .backup-section-title
/// panels.css:57）：13px/500、glass-label、uppercase、
/// 字距 0.5、padding 0/4、上下 margin 8——与通用
/// SectionHeader（14/600）是两个形态，不可代用。
struct BackupSectionTitle: View {
    var text: String
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    var body: some View {
        Text(text)
            .font(.system(size: f13, weight: .medium))
            .foregroundStyle(T.glassLabel)
            .tracking(0.5)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

struct SetRow: View {
    var title: String
    var meta: String? = nil
    /// 警示后缀（B3/B4）：主 meta 保持 glass-label
    /// 色，仅后缀段着 warning 色、以空格续接。
    var warnSuffix: String? = nil
    var icon: String? = nil
    var chevron: Bool = true
    var action: () -> Void
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    // 字形封顶同源度量（impl_dt_layout_resilience）。
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        // 字形封顶：callout 字形在大字号
                        // 档达 ≈52pt、溢出 24 槽压标题——
                        // 封顶至槽宽 24，默认档逐值不变。
                        .font(.system(size: min(f16, 24)))
                        .foregroundStyle(T.accent)
                        .frame(width: 24, height: 24)
                }
                // 标题→meta 盒距 6（M1）：Web
                // .item-left gap 4 + .set-row
                // .item-meta margin-top 2 合成。
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: f16, weight: .semibold))
                        .foregroundStyle(T.textMain)
                    if let meta {
                        // meta 色（C2）：Web .item-meta
                        // 经级联覆盖实际渲染 glass-label
                        // 色，两端统一走 T.glassLabel。
                        HStack(spacing: 0) {
                            Text(meta)
                                .foregroundStyle(T.glassLabel)
                            if let warnSuffix {
                                Text(" " + warnSuffix)
                                    .foregroundStyle(T.warning)
                            }
                        }
                        .font(.system(size: f12))
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: f18))
                        .foregroundStyle(
                            T.textSecondary.opacity(0.45))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: 0))
    }
}

/// 备份页专用行（S6，Web .backup-row panels.css:78）：
/// 内距 16/18、图标槽 28（Web 为专用蓝色描边 SVG，
/// 原生 SF 同色承接、槽宽对齐）、标题 16（650→600
/// 定案口径）、描述 13 且走 .backup-row-desc 的
/// glass-label 色、右箭 18 @45%。与 SetRow（设置导
/// 航行）是两个形态，不再借用。
struct BackupRow: View {
    var title: String
    var desc: String
    var icon: String
    var action: () -> Void
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    // 字形封顶同源度量（impl_dt_layout_resilience）。
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    // 字形封顶：body 字形在大字号档达
                    // ≈55pt、溢出 28 槽压标题——封顶至
                    // 槽宽 28，默认档逐值不变。
                    .font(.system(size: min(f17, 28)))
                    .foregroundStyle(T.accent)
                    .frame(width: 28, height: 28,
                           alignment: .leading)
                // 标题→描述 6（.backup-row-title
                // margin-bottom 6）。
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: f16, weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(desc)
                        .font(.system(size: f13))
                        .foregroundStyle(T.glassLabel)
                }
                Spacer()
                Text("›")
                    .font(.system(size: f18))
                    .foregroundStyle(
                        T.textSecondary.opacity(0.45))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle(radius: 0))
    }
}

// ── 设置页（对齐 Web SettingsView） ─────────────────
struct SettingsView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var langStore: LangStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var nav = SettingsNav()
    @AppStorage("lastExportTs") private var lastExportTs: Double = 0
    @AppStorage("lastEditTs") private var lastEditTs: Double = 0
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote)
    private var f13_6: CGFloat = 13.6
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    final class SettingsNav: ObservableObject {
        @Published var route: Sub?
    }

    /// MCP 桥协调器（M1）：桥行 meta 随链路状态走。
    @ObservedObject private var bridge =
        BridgeCoordinator.shared

    enum Sub: Identifiable {
        case backup, gestures, language, diag, bridge,
             weather, permissions
        var id: String {
            switch self {
            case .backup: return "backup"
            case .gestures: return "gestures"
            case .language: return "language"
            case .diag: return "diag"
            case .bridge: return "bridge"
            case .weather: return "weather"
            case .permissions: return "permissions"
            }
        }
    }

    // 主页天气行副标题 = 固定说明键
    // settings.weather_sub（数据源令牌配置），
    // 不再合成双 key 来源状态；逐源状态只在
    // WeatherView 二级页呈现（sourceWord /
    // effectiveText，键 builtin/custom/unset /
    // effective_* 仍归该页消费）。

    /// 新鲜度（Web 口径）：上次备份 {when}；≥2 天追加
    /// 「· {n} 天前」；超 7 天且期间有编辑 → 警示。
    private var backupStale: Bool {
        guard lastExportTs > 0 else { return false }
        let age = Date().timeIntervalSince1970 - lastExportTs
        return age > 7 * 86400 && lastEditTs > lastExportTs
    }

    /// 主文案（B2）：未备份 = 「尚未导出过备份」
    /// （settings.backup_never）；否则「上次备份
    /// {when}」，≥2 天以「 · 」续天数段。
    private var freshnessMain: String {
        if lastExportTs <= 0 {
            return Lang.t("settings.backup_never")
        }
        var s = Lang.tf("settings.backup_fresh",
                        ["when": Fmt.backupWhen(lastExportTs)])
        let days = Int((Date().timeIntervalSince1970
            - lastExportTs) / 86400)
        if days >= 2 {
            s += " · " + Lang.tf(
                "settings.backup_days_ago",
                ["n": "\(days)"])
        }
        return s
    }

    /// 警示后缀（B3/B4）：仅此段着 warning 色、以
    /// 空格续接主文案（Web settings.rs 口径）。
    private var freshnessWarn: String? {
        backupStale
            ? Lang.t("settings.backup_stale_warn") : nil
    }

    var body: some View {
        ChromeView(title: Lang.t("settings.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(
                        text: Lang.t("settings.appearance"),
                        topPad: 4)
                    // 文字大小跟随系统（Dynamic Type）：Web
                    // 的分级是接不到系统设置时的替代，原生
                    // 有系统 API 走更优路，不再自设分级。
                    HStack {
                        // 标题→副文案盒距 4（M1）：
                        // Web 外观行只有 .item-left
                        // gap 4、无 meta margin-top。
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Lang.t("settings.font_size"))
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t(
                                "settings.font_system_note"))
                                .font(.system(size: f12))
                                .foregroundStyle(T.textSecondary)
                        }
                        Spacer()
                        Text(Lang.t("settings.follow_system"))
                            .font(.system(size: f13))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.cardL)

                    // 组距账（S1）：外观卡 = Web
                    // .list-group 口径 margin-bottom
                    // 24 + page-gap 12 + 组头内联 4
                    // = 40（卡底→数据组头文字）。
                    SectionHeader(text: Lang.t("settings.data"),
                                  topPad: 40)
                    VStack(spacing: 0) {
                        SetRow(title: Lang.t("settings.backup"),
                               meta: freshnessMain,
                               warnSuffix: freshnessWarn) {
                            nav.route = .backup
                        }
                        rowDivider
                        // 语言行 meta = 当前生效语言本
                        // 名（随 store 解析/选定走，不
                        // 再写死「简体中文」，立项 I2）。
                        SetRow(title: Lang.t("settings.language"),
                               meta: LangStore.nativeName(
                                   langStore.code)) {
                            nav.route = .language
                        }
                        rowDivider
                        SetRow(title: Lang.t("gestures.title"),
                               meta: Lang.t(
                                   "gestures.settings_sub")) {
                            nav.route = .gestures
                        }
                        rowDivider
                        SetRow(title: Lang.t("settings.diag")) {
                            nav.route = .diag
                        }
                        rowDivider
                        // MCP 桥行（M1）：meta = 当前
                        // 链路状态文案（协调器状态键）。
                        SetRow(title: Lang.t("settings.bridge"),
                               meta: Lang.t(
                                   bridge.linkStateKey)) {
                            nav.route = .bridge
                        }
                        rowDivider
                        // 权限中心（impl_permission_
                        // center）：声明矩阵的运行时
                        // 收口——逐项真读状态、可请求
                        // 项在页内走各自框架正道 API。
                        SetRow(title: Lang.t("perm.title"),
                               meta: Lang.t(
                                   "perm.settings_sub")) {
                            nav.route = .permissions
                        }
                    }
                    .glassCard(radius: Radius.panel)

                    // 天气组（分组方案 A）：整组下移至
                    // 数据组之后、关于组之前，恢复 Web
                    // 「外观 → 数据 → 关于」主序。主页
                    // 只留入口行（副标题 = 固定说明键
                    // settings.weather_sub），表单移入
                    // WeatherView
                    // 二级页（与数据组同为导航行形态）。
                    // 组距账（S1）：数据卡 = Web
                    // .backup-card 口径 margin-bottom
                    // 16 + page-gap 12 + 组头内联 4
                    // = 32。命名处置：组头与入口行同用
                    // settings.weather——组头是分区标
                    // 签、行是唯一目的地入口，不另造
                    // 「天气 Key」键（键数净账锁定）。
                    SectionHeader(
                        text: Lang.t("settings.weather"),
                        topPad: 32)
                    SetRow(title: Lang.t("settings.weather"),
                           meta: Lang.t(
                               "settings.weather_sub")) {
                        nav.route = .weather
                    }
                    .glassCard(radius: Radius.panel)

                    // 组距账（S1 重推）：天气卡改与
                    // 数据组同型导航行卡（.backup-card
                    // 口径 margin-bottom 16）+ page-gap
                    // 12 + 组头内联 4 = 32。
                    SectionHeader(text: Lang.t("settings.about"),
                                  topPad: 32)
                    VStack(spacing: 0) {
                        HStack {
                            Text(Lang.t("settings.version"))
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("0.9.66")
                                .font(.system(size: f14))
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        rowDivider
                        HStack {
                            Text(Lang.t("settings.contact"))
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("overcanopies@gmail.com")
                                // 值字号（M7）：Web 关于
                                // 行内联 0.85rem ≈ 13.6。
                                .font(.system(size: f13_6))
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .glassCard(radius: Radius.panel)

                    Text(Lang.t("settings.footer"))
                        .font(.system(size: f12).italic())
                        .foregroundStyle(
                            T.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .settingsContentFrame()
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { nav.route != nil },
            set: { if !$0 { nav.route = nil } })) {
            switch nav.route {
            case .backup:
                BackupView(library: library)
            case .gestures:
                GesturesView()
            case .language:
                LanguageView()
            case .diag:
                DiagView(library: library)
            case .bridge:
                BridgeSettingsView()
            case .weather:
                WeatherView()
            case .permissions:
                PermissionsView()
            case nil:
                EmptyView()
            }
        }
        .onAppear {
            // 页进入行（G5，Web SET settings enter 口
            // 径；转场后缀原生系统转场改判不带）。
            DiagLog.shared.log(.info, "SET settings enter")
        }
        // 自检驱动注册（U5）：设置根面——分组结
        // 构读 + 二级页路由动作（与各 SetRow 点按
        // 同体：直写 nav.route）；语言呈现腿经
        // LangStore 读本面 lang 状态对读。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.view", kind: "page",
                instance: "-",
                actions: [
                    "openBackup": { _ in
                        nav.route = .backup
                    },
                    "openLanguage": { _ in
                        nav.route = .language
                    },
                    "openGestures": { _ in
                        nav.route = .gestures
                    },
                    "openDiag": { _ in
                        nav.route = .diag
                    },
                    "openBridge": { _ in
                        nav.route = .bridge
                    },
                    "openWeather": { _ in
                        nav.route = .weather
                    },
                    "openPermissions": { _ in
                        nav.route = .permissions
                    },
                    "closeRoute": { _ in
                        nav.route = nil
                    },
                ],
                state: [
                    "route": { nav.route?.id ?? "" },
                    "lang": { langStore.code },
                    "bridgeLink": { bridge.linkState },
                    "sections": {
                        "appearance,data,weather,about"
                    },
                    "version": {
                        Bundle.main.object(
                            forInfoDictionaryKey:
                                "CFBundleShortVersionString")
                            as? String ?? ""
                    },
                ])
        })
    }

    private var rowDivider: some View {
        // 分隔线色（M8）：Web --border-color
        // 浅 0.05 / 深 0.10 = T.borderSoft；此前
        // glassBorder 0.16 × 0.5 ≈ 0.08 两头都偏。
        Rectangle()
            .fill(T.borderSoft)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}

// ── 备份页（Web 口径：导出先确认、导入先选文件校验
// 后确认、页内 toast、最近操作结构化、新鲜度横幅） ──
struct BackupView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var langStore: LangStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = BackupUI()
    @AppStorage("lastExportTs") private var lastExportTs: Double = 0
    @AppStorage("lastEditTs") private var lastEditTs: Double = 0
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f18: CGFloat = 18
    @ScaledMetric(relativeTo: .title3)
    private var f19: CGFloat = 19
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2)
    private var f9: CGFloat = 9
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13

    final class BackupUI: ObservableObject {
        @Published var confirmExport = false
        @Published var showImporter = false
        @Published var confirmImport = false
        @Published var shareURL: URL?
        @Published var toast: Toast?
        struct Toast: Identifiable {
            let id = UUID()
            var text: String
            var isError: Bool
        }
    }

    private var stale: Bool {
        guard lastExportTs > 0 else { return false }
        let age = Date().timeIntervalSince1970 - lastExportTs
        return age > 7 * 86400 && lastEditTs > lastExportTs
    }

    private var ops: [Library.BackupOp] {
        Library.loadOps()
    }

    // hero 描述（M2 分段拼接）：五段 Text 链在
    // body 内联会触发类型检查超时，逐段落 let
    // 后逐步组合；段内容与颜色口径不变（分隔
    // 点 glassLabel.opacity(0.3)）。段色必须用
    // foregroundColor（返回 Text 本体）；用
    // foregroundStyle 段会变成 some View——
    // 不再是 Text，五段 + 拼接先超时、拆开后
    // 直接类型不成立（0.9.43 构建实证）。
    private var heroDesc: Text {
        let seg1 = Text(Lang.t("backup.last") + " "
                        + Fmt.backupWhen(lastExportTs))
            .foregroundColor(T.glassLabel)
        let sep1 = Text(" · ")
            .foregroundColor(T.glassLabel.opacity(0.3))
        let seg2 = Text("\(library.memos.count) "
                        + Lang.t("backup.memos"))
            .foregroundColor(T.glassLabel)
        let sep2 = Text(" · ")
            .foregroundColor(T.glassLabel.opacity(0.3))
        let seg3 = Text(
            "\(library.referencedAttachmentCount()) "
            + Lang.t("backup.attachments"))
            .foregroundColor(T.glassLabel)
        // 五段一次相加仍超时：两两相加、每步显式
        // 标注 Text 类型，逐段收窄类型检查。
        let left: Text = seg1 + sep1
        let mid: Text = left + seg2
        let right: Text = mid + sep2
        return right + seg3
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ChromeView(title: Lang.t("settings.backup"),
                       onBack: { dismiss() }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 标题→描述间距 19（M2）：Web
                        // .backup-hero-title margin-bottom
                        // 5 + .backup-hero-top margin-bottom
                        // 14 合成。
                        VStack(alignment: .leading, spacing: 19) {
                            // hero 度量（S5，Web .backup-hero）：
                            // 标题 18/700、卡 radius 30、
                            // padding 18。
                            Text(Lang.t("backup.hero_title"))
                                .font(.system(size: f18, weight: .bold))
                                .foregroundStyle(T.textMain)
                            // 描述（M2）：分隔点在 Web 为
                            // 独立 span opacity 0.3，分段
                            // 拼接承接（各段自带色，外层
                            // 只给字号避免覆盖段色）。
                            heroDesc
                                .font(.system(size: f13))
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(18)
                        .glassCard(radius: Radius.panelHero)

                        // 超期横幅（C3）：独立横幅卡——
                        // radius 30、0.5px warning 边、
                        // 内距横 18 纵 12、13px/1.5
                        // warning 色，hero 后下距 18。
                        if stale {
                            Text(Lang.t("backup.stale_banner"))
                                .font(.system(size: f13))
                                .lineSpacing(6.5)
                                .foregroundStyle(T.warning)
                                .frame(maxWidth: .infinity,
                                       alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(
                                    T.contentBg,
                                    in: RoundedRectangle(
                                        cornerRadius: Radius.panelHero))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: Radius.panelHero)
                                        .stroke(T.warning,
                                                lineWidth: 0.5))
                                .padding(.top, 18)
                        }

                        // Web 备份页无「本地备份」节标题
                        // （C4 已删）：hero/横幅后直入行卡，
                        // 间隔沿 hero 下距口径 18。
                        VStack(spacing: 0) {
                            // 导出/导入行（S6）：专用
                            // BackupRow（Web .backup-row
                            // 度量），不再借 SetRow。
                            BackupRow(
                                title: Lang.t(
                                    "backup.export_title"),
                                desc: Lang.t(
                                    "backup.export_desc"),
                                icon: "square.and.arrow.up") {
                                ui.confirmExport = true
                            }
                            Rectangle()
                                .fill(T.borderSoft)
                                .frame(height: 0.5)
                                .padding(.horizontal, 18)
                            BackupRow(
                                title: Lang.t(
                                    "backup.import_title"),
                                desc: Lang.t(
                                    "backup.import_desc"),
                                icon: "square.and.arrow.down") {
                                ui.showImporter = true
                            }
                        }
                        .glassCard(radius: Radius.panel)
                        .padding(.top, 18)

                        Text(Lang.t("backup.icloud_note"))
                            .font(.system(size: f13))
                            // 行高/顶距（M5）：Web
                            // .backup-note 13px/1.55、
                            // margin-top 10。
                            .lineSpacing(7)
                            .foregroundStyle(T.glassLabel)
                            .padding(.horizontal, 4)
                            .padding(.top, 10)

                        if !ops.isEmpty {
                            // 节标题（S3）：Web 专用
                            // .backup-section-title 形态，
                            // 不再借通用 SectionHeader。
                            BackupSectionTitle(
                                text: Lang.t("backup.history"))
                            VStack(spacing: 0) {
                                ForEach(Array(ops.prefix(6)
                                    .enumerated()), id: \.offset) {
                                    idx, op in
                                    opRow(op)
                                    if idx < min(ops.count, 6) - 1 {
                                        Rectangle()
                                            .fill(T.borderSoft)
                                            .frame(height: 0.5)
                                            .padding(
                                                .horizontal, 16)
                                    }
                                }
                            }
                            .glassCard(radius: Radius.panel)
                        }
                    }
                    .settingsContentFrame()
                }
            }
            if let toast = ui.toast {
                // 全宽条（S4，Web .backup-toast）：左右
                // 16、底 = safe + 16（根 ZStack 底即
                // safe 底，与首页撤销条 C-A1 同前提）、
                // radius 28 overlay 档、padding 14/16、
                // gap 10、图标 19 描边形、文案 14/500
                // 行高 1.35；成功图标走 --color-success
                // 绿（此前误用 accent 蓝）。这是备份页
                // 的 toast，与首页撤销条同 Web 组件、
                // 各自实例，口径分开。此前居中胶囊为
                // 自创形态（前轮 C8 残余）。
                HStack(spacing: 10) {
                    Image(systemName: toast.isError
                        ? "exclamationmark.circle"
                        : "checkmark.circle")
                        .font(.system(size: f19))
                        .foregroundStyle(toast.isError
                            ? T.danger : T.success)
                    Text(toast.text)
                        .font(.system(size: f14,
                                      weight: .medium))
                        .lineSpacing(5)
                        .foregroundStyle(T.textMain)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .overlayCard(radius: Radius.panel)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom)
                    .combined(with: .opacity))
            }
            if ui.confirmExport || ui.confirmImport {
                backupConfirmSheet
                    .transition(.opacity)
                    .animation(.spring(response: 0.25,
                                       dampingFraction: 0.86),
                               value: ui.confirmExport
                                   || ui.confirmImport)
            }
        }
        .animation(.spring(response: 0.28,
                           dampingFraction: 0.86),
                   value: ui.toast?.id.uuidString ?? "")
        .task(id: ui.toast?.id) {
            guard ui.toast != nil else { return }
            let secs = (ui.toast?.isError ?? false) ? 6.0 : 3.0
            try? await Task.sleep(
                for: .seconds(secs))
            ui.toast = nil
        }

        .fileImporter(isPresented: Binding(
            get: { ui.showImporter },
            set: { ui.showImporter = $0 }),
            allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result {
                library.pickedImportName =
                    url.lastPathComponent
                if library.stageImport(from: url) {
                    ui.confirmImport = true
                } else {
                    library.recordOp(kind: "import", ok: false,
                                     detail: "")
                    showToast(
                        Lang.t("status.import_invalid"),
                        isError: true)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url, onComplete: {
                    completed, error in
                    // toast 锚点后移到分享完成（BK-3）：
                    // 「文件已分享」只在分享真实完成时
                    // 弹；取消不弹、失败记 Diag 一行。
                    if completed {
                        showToast(
                            Lang.t("status.shared"),
                            isError: false)
                    } else if let error {
                        DiagLog.shared.log(.warn,
                            "BACKUP 分享未完成: \(error)")
                    }
                })
            }
        }
        .onAppear {
            // 页进入行（G5，Web BACKUP backup enter）。
            DiagLog.shared.log(.info, "BACKUP backup enter")
        }
        // 自检驱动注册（U5）：备份页状态腿——导
        // 出行在位与最近导出时刻读；导出触发本
        // 体走确认底表 + 分享面（系统面归人
        // 工），本面不代行导出。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.backup",
                kind: "page",
                instance: "-",
                state: [
                    "lastExportTs": {
                        "\(Int(lastExportTs))"
                    },
                    "memoCount": {
                        "\(library.memos.count)"
                    },
                ])
        })
    }

    /// 备份确认底表（C6 定案形态）：透明遮罩点按取
    /// 消；卡左右 14、底距 safe+14、max-width 600、
    /// radius 28；标题 18/700 居中、消息 13/1.45 次
    /// 级居中；按钮纵列 gap 10、高 44、radius 999，
    /// 主钮 accent 0.86 底白字、取消钮内容档。进场
    /// 250ms 弹簧仅淡入无位移（定案）。
    /// padding 静态账（Web panels.css:213-224，J1 结
    /// 转项以源码定案）：scrim padding 0 14px、
    /// padding-bottom safe+14（原生外层横 14/底
    /// safe+14 已对齐）；.backup-modal padding
    /// 14px 14px calc(14px + safe)——卡内底距含
    /// safe，与外层 scrim 底距叠加（Web 同账）。
    private var backupConfirmSheet: some View {
        let isExport = ui.confirmExport
        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(maxWidth: .infinity,
                           maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        ui.confirmExport = false
                        ui.confirmImport = false
                    }
                VStack(spacing: 0) {
                    Text(isExport
                        ? Lang.t("backup.export_title")
                        : Lang.t("backup.import_title"))
                        .font(.system(size: f18,
                                      weight: .bold))
                        .foregroundStyle(T.textMain)
                    Text(isExport
                        ? Lang.t("backup.export_msg")
                        : Lang.t("backup.import_msg"))
                        .font(.system(size: f13))
                        .lineSpacing(6)
                        .foregroundStyle(T.textSecondary)
                        .multilineTextAlignment(.center)
                        // 标题→消息 12、消息→按钮 12
                        // （M3，Web panels.css:213,214）。
                        .padding(.top, 12)
                    VStack(spacing: 10) {
                        Button {
                            ui.confirmExport = false
                            ui.confirmImport = false
                            if isExport {
                                if let url = library
                                    .exportZip() {
                                    // 生成成功只呈现分享面板；
                                    // 「文件已分享」toast 锚在
                                    // 分享完成（.sheet 的
                                    // onComplete，BK-3）。
                                    ui.shareURL = url
                                } else {
                                    let reason = library
                                        .lastExportError
                                        ?? Lang.t(
                                            "status.unknown_error")
                                    showToast(
                                        Lang.tf(
                                            "status.export_failed",
                                            ["e": reason]),
                                        isError: true)
                                }
                            } else {
                                // 成败按 ImportOutcome 分支
                                // （BK-1）：计数未知走无计数
                                // 成功文案（复用记录口径键
                                // backup.hist_restored），不
                                // 许误报失败——数据其实已换。
                                switch library.commitStagedImport() {
                                case .success(let stats):
                                    if let stats {
                                        showToast(
                                            Lang.tf(
                                                "status.imported",
                                                ["n": "\(stats.0)",
                                                 "m": "\(stats.1)"]),
                                            isError: false)
                                    } else {
                                        showToast(
                                            Lang.t("backup.hist_restored"),
                                            isError: false)
                                    }
                                case .failure:
                                    showToast(
                                        Lang.t("status.import_error"),
                                        isError: true)
                                }
                            }
                        } label: {
                            Text(isExport
                                ? Lang.t("backup.confirm_export")
                                : Lang.t("backup.confirm_import"))
                                // 按钮字（M3）：Web
                                // .backup-btn 14/650 →
                                // 14/600 定案口径。
                                .font(.system(
                                    size: f14,
                                    weight: .semibold))
                                .foregroundStyle(T.onAccent)
                                .frame(maxWidth: .infinity)
                                // 定高改最小高（布局韧性批）：
                                // f14 行高在大字号档超 44、字
                                // 形溢出钮面——底表为流式布局，
                                // 钮随行高生长、默认档恒 44。
                                .frame(minHeight: 44)
                                .background(
                                    T.accent.opacity(0.86),
                                    in: RoundedRectangle(
                                        cornerRadius: Radius.pill))
                        }
                        .buttonStyle(.plain)
                        Button {
                            ui.confirmExport = false
                            ui.confirmImport = false
                        } label: {
                            Text(Lang.t("action.cancel"))
                                .font(.system(
                                    size: f14,
                                    weight: .semibold))
                                .foregroundStyle(T.textMain)
                                .frame(maxWidth: .infinity)
                                // 定高改最小高（布局韧性批）：
                                // 同确认钮口径，默认档恒 44。
                                .frame(minHeight: 44)
                                .background(
                                    T.contentBg,
                                    in: RoundedRectangle(
                                        cornerRadius: Radius.pill))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom,
                         14 + geo.safeAreaInsets.bottom)
                .frame(maxWidth: 600)
                .glassCard(radius: Radius.panel)
                .padding(.horizontal, 14)
                .padding(.bottom,
                         geo.safeAreaInsets.bottom + 14)
            }
        }
    }

    private func showToast(_ text: String, isError: Bool) {
        ui.toast = BackupUI.Toast(text: text, isError: isError)
    }

    /// 操作标题（C10）：记录结构无消息字段，按
    /// kind/ok 映射 Web 的记录消息——导出成功恒走
    /// 系统分享 = 「文件已分享」（「备份已下载」是
    /// Web 下载路消息，原生不适用）、导入成功 =
    /// 「从本地文件恢复」、失败 = 导出失败/导入失败。
    private func opMessage(_ op: Library.BackupOp)
        -> String {
        switch (op.kind, op.ok) {
        case ("export", true):
            return Lang.t("status.shared")
        case ("import", true):
            return Lang.t("backup.hist_restored")
        case ("export", false):
            return Lang.t("backup.hist_export_failed")
        default:
            return Lang.t("backup.hist_import_failed")
        }
    }

    /// 操作副行（C10）：「{时间} · {文件名}」；
    /// 失败记录无文件名时只显时间。
    private func opSub(_ op: Library.BackupOp) -> String {
        let stamp = Fmt.fullStamp(op.ts)
        if op.detail.isEmpty { return stamp }
        return stamp + " · " + op.detail
    }

    private func opRow(_ op: Library.BackupOp) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(op.ok ? Color.green : T.danger)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(opMessage(op))
                    .font(.system(size: f14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(opSub(op))
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            // 类型徽章（C10）：9px/700/大写、内距
            // 1/6、radius 999、玻璃边。
            Text(op.kind == "export"
                ? Lang.t("backup.kind_export")
                : Lang.t("backup.kind_restore"))
                .font(.system(size: f9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(T.glassControlTint, in: Capsule())
                .overlay(
                    Capsule().stroke(T.glassBorder,
                                     lineWidth: 0.5))
        }
        // 行内距（M4）：Web 历史行 padding 12/14。
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// ── 手势速览页（文案走 Web 语言包 gestures.*，
// 原生 i18n I2 换键） ────────────────────────────
struct GesturesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var langStore: LangStore
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .title)
    private var f25: CGFloat = 25
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12

    private var rows: [(String, String, String)] {
        [
            ("hand.draw", Lang.t("gestures.swipe_name"),
             Lang.t("gestures.swipe_desc")),
            ("hand.tap", Lang.t("gestures.longpress_name"),
             Lang.t("gestures.longpress_desc")),
            ("text.cursor", Lang.t("gestures.slash_name"),
             Lang.t("gestures.slash_desc")),
            ("rectangle.split.2x1",
             Lang.t("gestures.columns_name"),
             Lang.t("gestures.columns_desc")),
            ("magnifyingglass",
             Lang.t("gestures.search_name"),
             Lang.t("gestures.search_desc")),
        ]
    }

    var body: some View {
        ChromeView(title: Lang.t("gestures.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()),
                            id: \.offset) { idx, row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.0)
                                // 字形封顶（布局韧性批）：
                                // 图示字形槽即字面 25，f25 在
                                // 大字号档达 ≈78pt 溢出槽压说
                                // 明文字——封顶至槽宽 25（图
                                // 示不随字号胀，平台行图标惯
                                // 例），默认档逐值不变。
                                .font(.system(size: min(f25, 25)))
                                .foregroundStyle(T.textMain)
                                .frame(width: 25, height: 25)
                            // 名称→说明盒距 6（M1）：
                            // Web .item-left gap 4 +
                            // .gesture-desc margin-top 2
                            // 合成（批 E 只落了后者）。
                            VStack(alignment: .leading,
                                   spacing: 6) {
                                Text(row.1)
                                    .font(.system(
                                        size: f14, weight: .semibold))
                                    .lineSpacing(5.6)
                                    .foregroundStyle(T.textMain)
                                Text(row.2)
                                    .font(.system(size: f12))
                                    .lineSpacing(6.6)
                                    .foregroundStyle(T.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        if idx < rows.count - 1 {
                            Rectangle()
                                .fill(T.borderSoft)
                                .frame(height: 0.5)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .glassCard(radius: Radius.panel)
                .settingsContentFrame()
            }
        }
        .onAppear {
            // 页进入行（G5，Web SET gestures enter）。
            DiagLog.shared.log(.info, "SET gestures enter")
        }
        // 自检驱动注册（U5）：手势页结构读抽样。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.gestures",
                kind: "page",
                instance: "-",
                state: [
                    "rows": { "\(rows.count)" },
                ])
        })
    }
}

// ── 天气页（设置页天气分组重构）：双 key 各自成
// 卡、逐字段即时提交；状态与生效来源由
// WeatherService.keySource 单一派生。key 只存本机
// UserDefaults，不入备份；提交只记来源、绝不记值。
struct WeatherView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var langStore: LangStore
    @StateObject private var ui = WeatherKeyEditor()
    @FocusState private var focusedField: Field?
    // 文字大小跟随系统（Dynamic Type 全量实装）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 字形封顶同源度量（impl_dt_layout_resilience）。
    @ScaledMetric(relativeTo: .subheadline)
    private var f15: CGFloat = 15
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    enum Field: Hashable {
        case qweather
        case caiyun
    }

    final class WeatherKeyEditor: ObservableObject {
        @Published var qweather: String =
            WeatherService.customKey("qweather")
        @Published var caiyun: String =
            WeatherService.customKey("caiyun")
        @Published var qweatherRevealed = false
        @Published var caiyunRevealed = false
        @Published var savedField: String?
        private var savedGeneration = 0

        func value(for name: String) -> String {
            name == "qweather" ? qweather : caiyun
        }

        func setValue(_ value: String, for name: String) {
            if name == "qweather" {
                qweather = value
            } else {
                caiyun = value
            }
        }

        func revealed(for name: String) -> Bool {
            name == "qweather"
                ? qweatherRevealed : caiyunRevealed
        }

        func toggleRevealed(for name: String) {
            if name == "qweather" {
                qweatherRevealed.toggle()
            } else {
                caiyunRevealed.toggle()
            }
        }

        /// 提交口径：去除全部空白（治粘贴带内部
        /// 换行/空格）；与现存值比较，无变化不写盘、
        /// 不清缓存、不打点。空值落盘为删键。
        func commit(_ name: String) {
            let raw = value(for: name)
            let cleaned = raw.filter { !$0.isWhitespace }
            if cleaned != raw {
                setValue(cleaned, for: name)
            }
            let existing = WeatherService.customKey(name)
            guard cleaned != existing else { return }
            if cleaned.isEmpty {
                UserDefaults.standard.removeObject(
                    forKey: "weatherKey_" + name)
            } else {
                UserDefaults.standard.set(
                    cleaned, forKey: "weatherKey_" + name)
            }
            WeatherService.shared
                .invalidateAfterKeyChange()
            flashSaved(name)
            logSaved()
        }

        func clear(_ name: String) {
            guard !WeatherService.customKey(name).isEmpty
            else { return }
            UserDefaults.standard.removeObject(
                forKey: "weatherKey_" + name)
            setValue("", for: name)
            WeatherService.shared
                .invalidateAfterKeyChange()
            flashSaved(name)
            logSaved()
        }

        func paste(_ name: String) {
            guard let raw = UIPasteboard.general.string
            else { return }
            let cleaned = raw.filter { !$0.isWhitespace }
            guard !cleaned.isEmpty else { return }
            setValue(cleaned, for: name)
            commit(name)
        }

        private func flashSaved(_ name: String) {
            savedGeneration += 1
            let generation = savedGeneration
            savedField = name
            Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: 1_200_000_000)
                if savedGeneration == generation {
                    savedField = nil
                }
            }
        }

        private func logSaved() {
            let qwSource = WeatherService
                .keySource("qweather").rawValue
            let cySource = WeatherService
                .keySource("caiyun").rawValue
            DiagLog.shared.log(.info,
                "SET weather key saved "
                + "qweather=\(qwSource) caiyun=\(cySource)")
        }
    }

    var body: some View {
        ChromeView(title: Lang.t("settings.weather"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(spacing: 6) {
                    weatherCard(name: "qweather",
                                titleKey:
                                    "settings.weather_qweather",
                                expectedLength: 32,
                                hintKey:
                                    "settings.weather_len_hint_qw")
                    weatherCard(name: "caiyun",
                                titleKey:
                                    "settings.weather_caiyun",
                                expectedLength: 16,
                                hintKey:
                                    "settings.weather_len_hint_cy")
                    Text(Lang.t("settings.weather_note"))
                        .font(.system(size: f12))
                        .foregroundStyle(T.textSecondary)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(16)
                        .glassCard(radius: Radius.cardL)
                }
                .settingsContentFrame()
            }
        }
        .onAppear {
            DiagLog.shared.log(.info, "SET weather enter")
        }
        .onDisappear {
            ui.commit("qweather")
            ui.commit("caiyun")
        }
        .onChange(of: focusedField) { field in
            if field != .qweather { ui.commit("qweather") }
            if field != .caiyun { ui.commit("caiyun") }
        }
        // 自检驱动注册（U5）：天气两槽字段面
        // （instance = 字段名）——setText 与页内
        // 字段同体（setValue 后经 commit 提交口
        // 径：清洗/比对/落盘/失效刷新同路），
        // clear 与页内清除钮同体（ui.clear）；
        // 状态只回来源与有无（keySource），绝不
        // 回 key 值（与桥 settings_get 同纪律）。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.weather",
                kind: "field",
                instance: "qweather",
                actions: [
                    "clear": { _ in ui.clear("qweather") },
                ],
                state: [
                    "source": {
                        WeatherService
                            .keySource("qweather")
                            .rawValue
                    },
                    "hasCustom": {
                        WeatherService
                            .keySource("qweather")
                            == .custom
                            ? "true" : "false"
                    },
                ],
                setText: { v in
                    ui.setValue(v, for: "qweather")
                    ui.commit("qweather")
                })
        })
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.weather",
                kind: "field",
                instance: "caiyun",
                actions: [
                    "clear": { _ in ui.clear("caiyun") },
                ],
                state: [
                    "source": {
                        WeatherService
                            .keySource("caiyun")
                            .rawValue
                    },
                    "hasCustom": {
                        WeatherService
                            .keySource("caiyun")
                            == .custom
                            ? "true" : "false"
                    },
                ],
                setText: { v in
                    ui.setValue(v, for: "caiyun")
                    ui.commit("caiyun")
                })
        })
    }

    private func field(for name: String) -> Field {
        name == "qweather" ? .qweather : .caiyun
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { ui.value(for: name) },
            set: { ui.setValue($0, for: name) })
    }

    private func sourceWord(
        _ source: WeatherService.KeySource) -> String {
        switch source {
        case .custom:
            return Lang.t("settings.weather_custom")
        case .builtin:
            return Lang.t("settings.weather_builtin")
        case .none:
            return Lang.t("settings.weather_unset")
        }
    }

    private func effectiveText(
        _ source: WeatherService.KeySource) -> String {
        switch source {
        case .custom:
            return Lang.t("settings.weather_effective_custom")
        case .builtin:
            return Lang.t("settings.weather_effective_builtin")
        case .none:
            return Lang.t("settings.weather_unset")
        }
    }

    private func weatherCard(
        name: String, titleKey: String,
        expectedLength: Int, hintKey: String) -> some View {
        let source = WeatherService.keySource(name)
        let draft = ui.value(for: name)
        let cleanedCount = draft.filter {
            !$0.isWhitespace
        }.count
        let showSaved = ui.savedField == name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(Lang.t(titleKey))
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Spacer()
                Text(showSaved
                     ? Lang.t("settings.weather_saved")
                     : sourceWord(source))
                    .font(.system(size: f12, weight:
                        (showSaved || source == .custom)
                            ? .bold : .regular))
                    .foregroundStyle(
                        (showSaved || source == .custom)
                            ? T.accent : T.textSecondary)
            }
            Text(effectiveText(source))
                .font(.system(size: f12))
                .foregroundStyle(T.glassLabel)
            HStack(spacing: 8) {
                Group {
                    if ui.revealed(for: name) {
                        TextField("",
                                  text: binding(for: name),
                                  prompt: Text(Lang.t(
                                    "settings.weather_unset")))
                    } else {
                        SecureField(
                            Lang.t("settings.weather_unset"),
                            text: binding(for: name))
                    }
                }
                .font(.system(size: f14))
                .foregroundStyle(T.textMain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focusedField,
                         equals: field(for: name))
                .onSubmit {
                    ui.commit(name)
                    focusedField = nil
                }
                Button {
                    ui.toggleRevealed(for: name)
                } label: {
                    Image(systemName: ui.revealed(for: name)
                          ? "eye.slash" : "eye")
                        // 字形封顶（布局韧性批）：subhead-
                        // line 字形在大字号档达 ≈49pt、
                        // 溢出 28 槽——封顶至槽宽 28，
                        // 默认档逐值不变。
                        .font(.system(size: min(f15, 28)))
                        .foregroundStyle(T.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Lang.t(
                    ui.revealed(for: name)
                        ? "settings.weather_hide"
                        : "settings.weather_show"))
            }
            if !draft.isEmpty
                && cleanedCount != expectedLength {
                // 长度只作软提示（现行注入实测和风
                // 32 位、彩云 16 位，非格式契约）：
                // 照常保存，不硬拦。
                Text(Lang.t(hintKey))
                    .font(.system(size: f12))
                    .foregroundStyle(T.warning)
            }
            HStack(spacing: 16) {
                Button(Lang.t("settings.weather_paste")) {
                    ui.paste(name)
                }
                if source == .custom {
                    Rectangle()
                        .fill(T.borderSoft)
                        .frame(width: 0.5, height: 14)
                    Button(Lang.t("settings.weather_clear")) {
                        ui.clear(name)
                    }
                }
            }
            .font(.system(size: f13))
            .foregroundStyle(T.accent)
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: Radius.cardL)
    }
}

// ── 语言页（原生 i18n I2，审计 E1–E4 按立项改判
// 关单）：每语言独立卡（E1：radius 32、卡间隔 6、
// 无分隔线）；状态纯文字 12px（E2：当前 accent/700、
// 余次级，无胶囊徽章无勾选）；五包全内置使状态坍
// 缩为「使用中/内置」（E3：Web 的下载/已下载是平
// 台妥协，原生不抄，此即终局）；点行即切换（E4：
// 写偏好 + 即时换包，LANG 打点在 LangStore.apply）。
// 首行「跟随系统」为原生三态（立项 §3 + 用户裁定
// 2026-11-26），副文案显示当前解析到的语言本名。
struct LanguageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var langStore: LangStore
    // 语义字体喂点（fix_dynamic_type_follow）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    var body: some View {
        ChromeView(title: Lang.t("lang.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(spacing: 6) {
                    followCard
                    ForEach(LangStore.codes,
                            id: \.self) { code in
                        langCard(code)
                    }
                }
                .settingsContentFrame()
            }
        }
        .onAppear {
            // 页进入行（G5）；切换打点随 i18n 落地
            // 于 LangStore（LANG applied /
            // follow-system ->，不在本页重复记）。
            DiagLog.shared.log(.info, "SET language enter")
        }
    }

    /// 跟随系统行：生效时状态「使用中」，未生效时
    /// 状态空；副文案恒显当前解析到的语言本名。
    private var followCard: some View {
        Button {
            langStore.applyFollowSystem()
        } label: {
            rowCard(
                name: Lang.t("lang.follow_system"),
                sub: LangStore.nativeName(langStore.code),
                status: langStore.followSystem
                    ? Lang.t("lang.active") : "",
                active: langStore.followSystem)
        }
        .buttonStyle(CardPressStyle())
    }

    private func langCard(_ code: String) -> some View {
        let active = !langStore.followSystem
            && langStore.code == code
        return Button {
            langStore.apply(code)
        } label: {
            rowCard(
                name: LangStore.nativeName(code),
                sub: LangStore.englishName(code),
                status: active
                    ? Lang.t("lang.active")
                    : Lang.t("lang.builtin"),
                active: active)
        }
        .buttonStyle(CardPressStyle())
    }

    /// 行卡形态（Web .list-item 口径）：名 16
    /// semibold + 英文名副文案 12 次级；状态纯文字
    /// 12px，当前 accent/700、余次级常规。
    private func rowCard(name: String, sub: String,
                         status: String,
                         active: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(sub)
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
            }
            Spacer()
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: f12, weight:
                        active ? .bold : .regular))
                    .foregroundStyle(active
                        ? T.accent : T.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .glassCard(radius: Radius.cardL)
    }
}

// ── 图片页（对齐 Web：页头返回+文件名标题，图 contain
// 适配可用区、大图只缩、小图不放大、区内居中） ──────
struct ImagePageView: View {
    var fileId: String?
    var urlString: String?
    var name: String
    var library: Library
    /// 返回出口（0.9.50）：转场宿主注入（pop 图片
    /// 页承载控制器）；在位时优先于环境 dismiss。
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var langStore: LangStore
    @StateObject private var loader = ImageLoader()
    @StateObject private var flags = ImgPageFlags()
    // 语义字体喂点（fix_dynamic_type_follow）：失
    // 败文案此前无字体、继承环境默认 body——与语
    // 义样式同通道，一并收口至喂点。
    @ScaledMetric(relativeTo: .body)
    private var f17: CGFloat = 17

    /// 打点去重标志（@State 宏在本工具链不可用，走
    /// ObservableObject 持有）。
    private final class ImgPageFlags: ObservableObject {
        @Published var loggedOpen = false
        @Published var loggedClose = false
        /// 可用区量测通道（U5）：body 的
        /// GeometryReader 回写（页宽与 availH，
        /// 与呈现判定同源同点），供 image.view
        /// 注册面的适配几何状态读。
        @Published var viewportW: CGFloat = 0
        @Published var availH: CGFloat = 0
    }

    /// 标题（Web 口径）：fileId 在时按 attachment-
    /// Name 查名序取真实名（清单优先 → 节点名兜
    /// 底），查无才用调用点传入名；URL 图无清单
    /// 名，用节点名（多为兜底「图片」）。
    private var displayName: String {
        if let fid = fileId,
           let real = library.attachmentName(for: fid) {
            return real
        }
        return name
    }

    /// 页头呈现名（用户 2026-11-26 定）：真实文件名
    /// 超过 12 字时只显前 12 字 + 「…」；截断仅作用
    /// 于呈现，Diag 的 IMGPAGE 行仍记全名。
    private var titleText: String {
        let n = displayName
        guard n.count > 12 else { return n }
        return String(n.prefix(12)) + "…"
    }

    private func logCloseOnce() {
        guard !flags.loggedClose else { return }
        flags.loggedClose = true
        DiagLog.shared.log(.info, "IMGPAGE close")
    }

    var body: some View {
        ChromeView(title: titleText, onBack: {
            logCloseOnce()
            if let onClose { onClose() } else { dismiss() }
        }) {
            GeometryReader { geo in
                // 可用区（Web .img-page-content 沿用
                // .page-content 口径，panels.css）：顶
                // 让 126、底让 40 + safeBottom。图判定
                // 与呈现同用 availH（0.9.34 的同源口径
                // 保留，本批只换让位数值对齐 Web，
                // 审计 L-4）。
                let availH = geo.size.height - 126
                    - 40 - geo.safeAreaInsets.bottom
                Group {
                    if let img = loader.image {
                        // 缩放查看（用户 2026-11-26 裁
                        // 定）：初始 contain 适配（判定高
                        // availH 与呈现同口径），捏合/双
                        // 击缩放、平移、动图播放在承载
                        // 视图内（ZoomableImageView）。
                        ZoomableImageView(
                            image: img,
                            viewport: CGSize(
                                width: geo.size.width,
                                height: availH))
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    } else if loader.failed {
                        Text(Lang.t("imgpage.load_failed"))
                            .font(.system(size: f17))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    }
                }
                .padding(.top, 126)
                .padding(.bottom,
                         40 + geo.safeAreaInsets.bottom)
                // 可用区回写（U5）：与上方 availH
                // 判定同点同源，探针/场景据此对读
                // 适配几何，不在消费方重算公式。
                .onAppear {
                    flags.viewportW = geo.size.width
                    flags.availH = availH
                }
                .onChange(of: geo.size) { s in
                    flags.viewportW = s.width
                    flags.availH = s.height - 126
                        - 40 - geo.safeAreaInsets.bottom
                }
            }
        }
        .onAppear {
            loader.load(fileId: fileId, urlString: urlString,
                        library: library)
        }
        .onChange(of: loader.image != nil) { ready in
            // IMGPAGE open 行（Web 口径）：图就绪后记，
            // 带文件名与自然像素尺寸（size 为点、乘
            // scale 还原像素——批 K F2，此前直记点数
            // 在 3× 机上只有 Web 的 1/3）；失败记
            // nat=error。
            guard ready, !flags.loggedOpen,
                  let img = loader.image else { return }
            flags.loggedOpen = true
            DiagLog.shared.log(.info,
                "IMGPAGE open name=\(displayName) "
                + "nat=\(Int(img.size.width * img.scale))x"
                + "\(Int(img.size.height * img.scale))")
        }
        .onChange(of: loader.failed) { failed in
            guard failed, !flags.loggedOpen else { return }
            flags.loggedOpen = true
            DiagLog.shared.log(.error,
                "IMGPAGE open name=\(displayName) nat=error")
        }
        .onDisappear {
            // 侧滑返回不走页头钮：兜底记 close（与钮
            // 路径去重，Web 只记钮、此为覆盖增强）。
            logCloseOnce()
        }
        // 自检驱动注册（U5）：图片页面——标题与
        // 适配几何状态读（fit = contain 适配式：
        // scale = min(availW/图宽, availH/图高,
        // 1)，大图只缩、小图不放大，与呈现判定
        // 同式）；close 与页头返回同体。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "image.view", kind: "page",
                instance: "-",
                actions: [
                    "close": { _ in
                        logCloseOnce()
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    },
                ],
                state: [
                    "title": { titleText },
                    "name": { displayName },
                    "hasImage": {
                        loader.image != nil
                            ? "true" : "false"
                    },
                    "failed": {
                        loader.failed
                            ? "true" : "false"
                    },
                    "natW": {
                        loader.image.map {
                            "\($0.size.width)"
                        } ?? ""
                    },
                    "natH": {
                        loader.image.map {
                            "\($0.size.height)"
                        } ?? ""
                    },
                    "availW": { "\(flags.viewportW)" },
                    "availH": { "\(flags.availH)" },
                    "fitW": {
                        guard let img = loader.image,
                              flags.viewportW > 0,
                              flags.availH > 0
                        else { return "" }
                        let s = min(
                            flags.viewportW
                                / img.size.width,
                            flags.availH
                                / img.size.height,
                            1)
                        return "\(img.size.width * s)"
                    },
                    "fitH": {
                        guard let img = loader.image,
                              flags.viewportW > 0,
                              flags.availH > 0
                        else { return "" }
                        let s = min(
                            flags.viewportW
                                / img.size.width,
                            flags.availH
                                / img.size.height,
                            1)
                        return "\(img.size.height * s)"
                    },
                ])
        })
    }
}

@main
struct MomentApp: App {
    // BGTask 注册（权限批矩阵 #21/#23）：须在启动
    // 完成前注册，App.init 是本应用最早的注册点；
    // 调度提交同在此（进后台时由桥生命周期观察
    // 再续提）。
    init() {
        MomentLiveOps.registerBackgroundTasks()
        MomentLiveOps.scheduleBackgroundTasks()
    }

    // 语言 store 先于 Library 声明：其 init 的存量
    // 判据须赶在 Library.load 开库建 moment.db 之前
    // （判据本体见 LangStore.hasExistingState）。
    @StateObject private var langStore = LangStore.shared
    @StateObject private var library = Library()
    /// 应用委托（fix_splash_flash_sequence）：仅
    /// 方向掩码一件职责——开屏方向锁 SB-8 的决定
    /// 面（LaunchOrientationGate），挂载在此。
    @UIApplicationDelegateAdaptor(MomentAppDelegate.self)
    private var appDelegate
    /// 开屏时序状态（fix_splash_flash_sequence）：
    /// 根持有、启动层与铬面探针同消费（状态机本
    /// 体在 MomentSplashHost）。
    @StateObject private var splashState = SplashState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                // S2 分流：安全模式先渲染 RescueView、
                // 不构建 ListView（判定已在 Library
                // .init 完成）；开屏宿主只在正常模式
                // 挂载（安全模式 didLoad 不置真、挂了
                // 会永久盖住救援页）。
                if library.bootIsSafe {
                    RescueView(library: library)
                } else {
                    ListView(library: library)
                }
                // 错误徽章挂根（G8）：全应用可见。
                ErrBadgeOverlay()
                // 开屏层（fix_splash_flash_sequence）：
                // 单承载——开屏是根层级内的一层、随
                // 根首帧同帧在位（无呈现接缝）；挂载
                // 条件与旧呈现器同口径（正常模式 &&
                // 资源就绪），安全模式不挂（挂了会盖
                // 住救援页）。
                if !library.bootIsSafe
                    && SplashOverlayView.resourcesReady {
                    SplashLaunchLayer(library: library,
                                      state: splashState)
                }
                // 看门狗浮条（S8）：挂在开屏之上——挂
                // 死时开屏正驻留，浮条必须压得住它。
                if library.watchdogFired
                    && !library.bootIsSafe {
                    WatchdogBar(library: library)
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .bottom)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            // 启动铬面探针（fix_splash_flash_
            // sequence）：根挂载、零尺寸不参与命中
            // ——窗口底色（开屏同源色 → 退出后根页
            // 底色）与方向门送达的单点（Moment
            // SplashHost 的 LaunchChromeProbe）。
            .background {
                LaunchChromeProbe(library: library,
                                  state: splashState)
            }
            .environmentObject(langStore)
            .onChange(of: library.didLoad) { ready in
                // 应用晚到就绪：浮条自撤（S8）。
                if ready { library.dismissWatchdog() }
            }
        }
            .onChange(of: scenePhase) { phase in
                // G2 哨兵收尾：退后台=正常收尾清哨兵，
                // 回前台续上——只有前台进程终止留痕。
                if phase == .background {
                    // E4/F-18 编辑冲刷：清哨兵前先经在
                    // 席注册表把在席编辑器的防抖保存立即
                    // 冲刷（saveNow 走现行保存单点，不另
                    // 起保存路）——后台被系统回收也不丢
                    // 最后 <0.6s 编辑（Web pagehide 保
                    // 险丝的等价物）。标题草稿不在模型
                    // 内、不被连带 commit，维持「手势返
                    // 回才 commit」的现口径（审计待裁项
                    // 8 的建议口径）。
                    if let mid = EditorSeatRegistry.shared
                        .currentMemoId,
                       EditorSeatRegistry.shared.saveNow() {
                        DiagLog.shared.log(.info,
                            "EDIT flush src=background "
                            + "memo=\(mid)")
                    }
                    Library.launchSuspend()
                } else if phase == .active {
                    Library.launchResume()
                }
            }
    }
}
import SwiftUI
import UIKit
import Foundation

struct NativeMomentSplash: View, Animatable {
    @Environment(\.colorScheme) private var colorScheme
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Group {
            if colorScheme == .dark {
                NativeSplashCanvas(artwork: .dark, progress: progress)
            } else {
                NativeSplashCanvas(artwork: .light, progress: progress)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme == .dark
            ? Color(red: 31.0 / 255, green: 31.0 / 255, blue: 33.0 / 255)
            : Color(red: 35.0 / 255, green: 121.0 / 255, blue: 220.0 / 255))
    }
}

private struct NativeSplashCanvas: View {
    private static let sourceWidth: CGFloat = 1179
    private static let sourceHeight: CGFloat = 2556
    private static let logoCenter = CGPoint(x: 589.5, y: 1113.5)
    private static let taglineCenter = CGPoint(x: 589, y: 1640)

    let artwork: NativeSplashArtwork
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = max(size.width / Self.sourceWidth, size.height / Self.sourceHeight)
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let foregroundScale = isPad ? min(scale, min(0.72, size.width / 1200)) : scale
            let artboardWidth = Self.sourceWidth * scale
            let artboardHeight = Self.sourceHeight * scale
            let offsetX = (size.width - artboardWidth) / 2
            let offsetY = (size.height - artboardHeight) / 2
            let amount = NativeSplashMotion.value(for: progress)
            let logoCenter = CGPoint(
                x: isPad ? size.width / 2 : offsetX + Self.logoCenter.x * scale,
                y: isPad ? size.height * 0.35 : offsetY + Self.logoCenter.y * scale
            )
            let taglineCenter = CGPoint(
                x: isPad ? size.width / 2 : offsetX + Self.taglineCenter.x * scale,
                y: isPad ? size.height * 0.69 : offsetY + Self.taglineCenter.y * scale
            )

            Canvas { context, canvasSize in
                let canvasScale = max(canvasSize.width / Self.sourceWidth, canvasSize.height / Self.sourceHeight)
                let canvasWidth = Self.sourceWidth * canvasScale
                let canvasHeight = Self.sourceHeight * canvasScale
                var backgroundContext = context
                backgroundContext.translateBy(x: (canvasSize.width - canvasWidth) / 2, y: (canvasSize.height - canvasHeight) / 2)
                backgroundContext.scaleBy(x: canvasScale, y: canvasScale)
                backgroundContext.fill(
                    Path(CGRect(x: 0, y: 0, width: Self.sourceWidth, height: Self.sourceHeight)),
                    with: artwork.background.shading
                )

                let logoScale = foregroundScale * (1 + 0.035 * amount)
                var logoContext = context
                logoContext.translateBy(
                    x: logoCenter.x - Self.logoCenter.x * logoScale,
                    y: logoCenter.y - Self.logoCenter.y * logoScale
                )
                logoContext.scaleBy(x: logoScale, y: logoScale)
                logoContext.fill(artwork.logo.base, with: artwork.logo.gradient.shading)
                var logoInterior = logoContext
                logoInterior.clip(to: artwork.logo.base)
                for detail in artwork.logo.details {
                    logoInterior.fill(detail.path, with: .color(.white.opacity(detail.opacity)))
                }

                let taglineScale = foregroundScale
                let taglineOffsetY = -0.009 * Self.sourceHeight * foregroundScale * amount
                var taglineContext = context
                taglineContext.translateBy(
                    x: taglineCenter.x - Self.taglineCenter.x * taglineScale,
                    y: taglineCenter.y - Self.taglineCenter.y * taglineScale + taglineOffsetY
                )
                taglineContext.scaleBy(x: taglineScale, y: taglineScale)
                taglineContext.fill(artwork.tagline.path, with: .color(artwork.tagline.color))
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }
}

private struct NativeSplashArtwork {
    // 绘制三件（NativeSplashGradient/Logo/
    // Tagline）与本类型均为文件私有：消费方只有
    // 同文件的 NativeSplashCanvas。（沿革：二轮
    // 曾为状态栏带区采样把背景渐变数值表跨文件
    // 公开、本类型随之去 private；采样去除后数
    // 值表整表退役、可见性复原，remove_
    // statusbar_sampling。）
    let background: NativeSplashGradient
    let logo: NativeSplashLogo
    let tagline: NativeSplashTagline

    static let light = load(theme: "light")
    static let dark = load(theme: "dark")

    private static func load(theme: String) -> NativeSplashArtwork {
        guard
            let url = Bundle.main.url(forResource: "MomentSplash-\(theme)-vector", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let resource = try? JSONDecoder().decode(NativeSplashVectorResource.self, from: data)
        else {
            // 降级呈现（AUD-E-01 根治）：旧口径解码
            // 失败即陷阱退出——开屏资源损坏 = 启动
            // 期必闪退、且发生在救援壳拦不住的呈现
            // 面。现降级为根色底 + 空图元（见
            // degraded），Diag 记行留证，永不 trap。
            DiagLog.shared.log(.error,
                "SPLASH artwork decode failed theme=\(theme)")
            return degraded(theme: theme)
        }

        let logoDetails = resource.logo.decoration.map { detail in
            NativeSplashLogoDetail(
                path: NativeSVGPath.parse(detail.d).applying(detail.transform.affineTransform),
                opacity: detail.opacity
            )
        }
        return NativeSplashArtwork(
            background: NativeSplashGradient(resource.background),
            logo: NativeSplashLogo(
                base: NativeSVGPath.parse(resource.logo.basePath),
                gradient: NativeSplashGradient(resource.logo.gradient),
                details: logoDetails
            ),
            tagline: NativeSplashTagline(
                path: NativeSVGPath.parse(resource.tagline.d).applying(resource.tagline.transform.affineTransform),
                color: Color(hex: resource.tagline.fill)
            )
        )
    }

    /// 解码失败降级件（AUD-E-01）：背景 = 主题根
    /// 色（T.bg 同值：浅 #F2F2F7 / 深 #000000）
    /// 双同色 stop 线性渐变；logo 与 tagline 为
    /// 空 Path（不绘制）——开屏只剩根色面，胜过
    /// 启动闪退。
    private static func degraded(theme: String)
        -> NativeSplashArtwork {
        let gradient = NativeSplashGradient(
            solid: theme == "dark"
                ? Color.black
                : Color(hex: "#F2F2F7"))
        return NativeSplashArtwork(
            background: gradient,
            logo: NativeSplashLogo(
                base: Path(), gradient: gradient,
                details: []),
            tagline: NativeSplashTagline(
                path: Path(), color: Color.clear))
    }
}

private struct NativeSplashVectorResource: Decodable {
    struct ViewBox: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let source: String
    let viewBox: ViewBox
    let background: NativeSplashGradientResource
    let logo: NativeSplashLogoResource
    let tagline: NativeSplashPathResource
}

private struct NativeSplashGradientResource: Decodable {
    struct Stop: Decodable {
        let offset: Double
        let color: String
        let opacity: Double
    }

    let start: [Double]
    let end: [Double]
    let stops: [Stop]
}

private struct NativeSplashLogoResource: Decodable {
    struct Detail: Decodable {
        let d: String
        let fill: String
        let opacity: Double
        let transform: [Double]
    }

    let bounds: [String: Double]
    let gradient: NativeSplashGradientResource
    let basePath: String
    let decoration: [Detail]
}

private struct NativeSplashPathResource: Decodable {
    let d: String
    let fill: String
    let opacity: Double
    let transform: [Double]
}

private struct NativeSplashGradient {
    let start: CGPoint
    let end: CGPoint
    let stops: [Gradient.Stop]

    init(_ resource: NativeSplashGradientResource) {
        // 下标守卫（AUD-E-01）：start/end 不足两元
        // 素时回退对角 (0,0)/(1,1)，不裸下标
        // trap；stops 为空回退透明双 stop，防空
        // Gradient 绘制异常。
        start = resource.start.count >= 2
            ? CGPoint(x: resource.start[0],
                      y: resource.start[1])
            : CGPoint(x: 0, y: 0)
        end = resource.end.count >= 2
            ? CGPoint(x: resource.end[0],
                      y: resource.end[1])
            : CGPoint(x: 1, y: 1)
        stops = resource.stops.isEmpty
            ? [Gradient.Stop(color: .clear, location: 0),
               Gradient.Stop(color: .clear, location: 1)]
            : resource.stops.map { stop in
                Gradient.Stop(
                    color: Color(hex: stop.color)
                        .opacity(stop.opacity),
                    location: CGFloat(stop.offset))
            }
    }

    /// 单色渐变（开屏降级件专用，AUD-E-01）。
    init(solid color: Color) {
        start = CGPoint(x: 0, y: 0)
        end = CGPoint(x: 1, y: 1)
        stops = [Gradient.Stop(color: color, location: 0),
                 Gradient.Stop(color: color, location: 1)]
    }

    var shading: GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end)
    }
}

private struct NativeSplashLogoDetail {
    let path: Path
    let opacity: Double
}

private struct NativeSplashLogo {
    let base: Path
    let gradient: NativeSplashGradient
    let details: [NativeSplashLogoDetail]
}

private struct NativeSplashTagline {
    let path: Path
    let color: Color
}

private extension Color {
    init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(raw, radix: 16) ?? 0xFFFFFF
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

private enum NativeSVGPath {
    private static let tokenRegex = try! NSRegularExpression(
        pattern: "[-+]?(?:\\d*\\.\\d+|\\d+\\.?\\d*)(?:[eE][-+]?\\d+)?|[A-Za-z]"
    )

    static func parse(_ data: String) -> Path {
        let nsData = data as NSString
        let matches = tokenRegex.matches(in: data, range: NSRange(location: 0, length: nsData.length))
        let tokens = matches.map { nsData.substring(with: $0.range) }
        var path = Path()
        var index = 0
        var command: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var previousCubicControl: CGPoint?
        var previousQuadraticControl: CGPoint?
        var previousCommand: Character?

        func isCommand(_ token: String) -> Bool {
            token.count == 1 && token.first?.isLetter == true && token.first?.isNumber == false
        }
        func hasNumbers(_ count: Int) -> Bool {
            guard index + count <= tokens.count else { return false }
            return (0..<count).allSatisfy { !isCommand(tokens[index + $0]) }
        }
        func number() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(tokens[index]) ?? 0)
        }
        func point(relative: Bool) -> CGPoint {
            let x = number()
            let y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        func reflected(_ control: CGPoint?) -> CGPoint {
            guard let control else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        while index < tokens.count {
            if isCommand(tokens[index]) {
                command = tokens[index].first
                index += 1
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    previousCubicControl = nil
                    previousQuadraticControl = nil
                    previousCommand = command
                    command = nil
                    continue
                }
            }
            guard let active = command else { continue }
            let relative = active.isLowercase
            switch active.uppercased() {
            case "M":
                guard hasNumbers(2) else { command = nil; continue }
                let destination = point(relative: relative)
                path.move(to: destination)
                current = destination
                subpathStart = destination
                previousCubicControl = nil
                previousQuadraticControl = nil
                previousCommand = active
                command = relative ? "l" : "L"
            case "L":
                guard hasNumbers(2) else { command = nil; continue }
                let destination = point(relative: relative)
                path.addLine(to: destination)
                current = destination
                previousCubicControl = nil
                previousQuadraticControl = nil
                previousCommand = active
            case "H":
                guard hasNumbers(1) else { command = nil; continue }
                let x = number()
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                previousCubicControl = nil
                previousQuadraticControl = nil
                previousCommand = active
            case "V":
                guard hasNumbers(1) else { command = nil; continue }
                let y = number()
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                previousCubicControl = nil
                previousQuadraticControl = nil
                previousCommand = active
            case "C":
                guard hasNumbers(6) else { command = nil; continue }
                let c1 = point(relative: relative)
                let c2 = point(relative: relative)
                let destination = point(relative: relative)
                path.addCurve(to: destination, control1: c1, control2: c2)
                current = destination
                previousCubicControl = c2
                previousQuadraticControl = nil
                previousCommand = active
            case "S":
                guard hasNumbers(4) else { command = nil; continue }
                let prior = previousCommand?.uppercased()
                let c1 = (prior == "C" || prior == "S") ? reflected(previousCubicControl) : current
                let c2 = point(relative: relative)
                let destination = point(relative: relative)
                path.addCurve(to: destination, control1: c1, control2: c2)
                current = destination
                previousCubicControl = c2
                previousQuadraticControl = nil
                previousCommand = active
            case "Q":
                guard hasNumbers(4) else { command = nil; continue }
                let control = point(relative: relative)
                let destination = point(relative: relative)
                path.addQuadCurve(to: destination, control: control)
                current = destination
                previousQuadraticControl = control
                previousCubicControl = nil
                previousCommand = active
            case "T":
                guard hasNumbers(2) else { command = nil; continue }
                let prior = previousCommand?.uppercased()
                let control = (prior == "Q" || prior == "T") ? reflected(previousQuadraticControl) : current
                let destination = point(relative: relative)
                path.addQuadCurve(to: destination, control: control)
                current = destination
                previousQuadraticControl = control
                previousCubicControl = nil
                previousCommand = active
            default:
                command = nil
            }
        }
        return path
    }
}

private enum NativeSplashMotion {
    static func value(for progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let peak: CGFloat = 0.46
        if clamped <= peak {
            return cubicBezierEase(clamped / peak)
        }
        return 1 - cubicBezierEase((clamped - peak) / (1 - peak))
    }

    private static func cubicBezierEase(_ input: CGFloat) -> CGFloat {
        let x = min(max(input, 0), 1)
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        var t = x

        for _ in 0..<16 {
            let inverse = 1 - t
            let sampleX = 3 * inverse * inverse * t * 0.4
                + 3 * inverse * t * t * 0.2
                + t * t * t
            if abs(sampleX - x) < 0.00001 { break }
            if sampleX < x {
                lower = t
            } else {
                upper = t
            }
            t = (lower + upper) / 2
        }

        let inverse = 1 - t
        return 3 * inverse * t * t + t * t * t
    }
}

private extension Array where Element == Double {
    var affineTransform: CGAffineTransform {
        guard count == 6 else { return .identity }
        return CGAffineTransform(a: self[0], b: self[1], c: self[2], d: self[3], tx: self[4], ty: self[5])
    }
}

struct NativeFailureSplashIcon: View {
    let colorScheme: ColorScheme

    private static let sourceSize: CGFloat = 1024

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / Self.sourceSize
            var canvas = context
            canvas.translateBy(
                x: (size.width - Self.sourceSize * scale) / 2,
                y: (size.height - Self.sourceSize * scale) / 2
            )
            canvas.scaleBy(x: scale, y: scale)

            let isDark = colorScheme == .dark
            let bounds = CGRect(x: 0, y: 0, width: Self.sourceSize, height: Self.sourceSize)
            if isDark {
                canvas.fill(
                    Path(bounds),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(hex: "#2A2A2C"), location: 0),
                            .init(color: Color(hex: "#222225"), location: 0.56),
                            .init(color: Color(hex: "#131316"), location: 1)
                        ]),
                        startPoint: CGPoint(x: 130, y: 0),
                        endPoint: CGPoint(x: 920, y: 1024)
                    )
                )
                canvas.fill(
                    Path(bounds),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color.white.opacity(0.075), location: 0),
                            .init(color: Color.white.opacity(0.025), location: 0.48),
                            .init(color: Color.clear, location: 1)
                        ]),
                        center: CGPoint(x: 486, y: 770),
                        startRadius: 0,
                        endRadius: 380
                    )
                )
            } else {
                canvas.fill(
                    Path(bounds),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color(hex: "#39B7FC"), location: 0),
                            .init(color: Color(hex: "#248EF2"), location: 0.52),
                            .init(color: Color(hex: "#0870E8"), location: 1)
                        ]),
                        startPoint: CGPoint(x: 0, y: 140),
                        endPoint: CGPoint(x: 1024, y: 884)
                    )
                )
                canvas.fill(
                    Path(bounds),
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: Color.clear, location: 0),
                            .init(color: Color.black.opacity(0.055), location: 0.58),
                            .init(color: Color.black.opacity(0.16), location: 1)
                        ]),
                        startPoint: CGPoint(x: 500, y: 0),
                        endPoint: CGPoint(x: 500, y: 1024)
                    )
                )
                canvas.fill(
                    Path(bounds),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: Color.white.opacity(0.18), location: 0),
                            .init(color: Color.white.opacity(0.07), location: 0.38),
                            .init(color: Color.clear, location: 1)
                        ]),
                        center: CGPoint(x: 494, y: 778),
                        startRadius: 0,
                        endRadius: 360
                    )
                )
            }

            let fullTrail = Self.makeTrail()
            canvas.stroke(
                fullTrail,
                with: .color(Color.white.opacity(isDark ? 0.06 : 0.07)),
                style: StrokeStyle(lineWidth: 42, lineCap: .round, lineJoin: .round)
            )

            let upperTail = Self.makeUpperTail()
            canvas.stroke(
                upperTail,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.white.opacity(0.005), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.07 : 0.055), location: 0.52),
                        .init(color: Color.white.opacity(isDark ? 0.42 : 0.36), location: 1)
                    ]),
                    startPoint: CGPoint(x: 110, y: 570),
                    endPoint: CGPoint(x: 520, y: 428)
                ),
                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
            )

            let mainSweep = Self.makeMainSweep()
            canvas.stroke(
                mainSweep,
                with: .color(Color.white.opacity(isDark ? 0.18 : 0.15)),
                style: StrokeStyle(lineWidth: 27, lineCap: .round, lineJoin: .round)
            )
            canvas.stroke(
                mainSweep,
                with: .color(Color.white.opacity(isDark ? 0.95 : 0.89)),
                style: StrokeStyle(lineWidth: 15, lineCap: .round, lineJoin: .round)
            )

            let lowerBend = Self.makeLowerBend()
            canvas.stroke(
                lowerBend,
                with: .color(Color.white.opacity(isDark ? 0.20 : 0.16)),
                style: StrokeStyle(lineWidth: 38, lineCap: .round, lineJoin: .round)
            )
            canvas.stroke(
                lowerBend,
                with: .color(Color.white.opacity(isDark ? 0.98 : 0.94)),
                style: StrokeStyle(lineWidth: 27, lineCap: .round, lineJoin: .round)
            )

            let lowerTail = Self.makeLowerTail()
            canvas.stroke(
                lowerTail,
                with: .color(Color.white.opacity(isDark ? 0.08 : 0.06)),
                style: StrokeStyle(lineWidth: 29, lineCap: .round, lineJoin: .round)
            )
            canvas.stroke(
                lowerTail,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.white.opacity(isDark ? 0.92 : 0.86), location: 0),
                        .init(color: Color.white.opacity(isDark ? 0.82 : 0.77), location: 0.48),
                        .init(color: Color.white.opacity(0.32), location: 1)
                    ]),
                    startPoint: CGPoint(x: 554, y: 864),
                    endPoint: CGPoint(x: 928, y: 780)
                ),
                style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 90, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panelS, style: .continuous))
        .accessibilityLabel(Lang.t("app.splash_icon_aria"))
    }

    private static func makeTrail() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 110, y: 570))
        path.addCurve(to: CGPoint(x: 520, y: 428), control1: CGPoint(x: 252, y: 468), control2: CGPoint(x: 402, y: 414))
        path.addCurve(to: CGPoint(x: 680, y: 452), control1: CGPoint(x: 610, y: 420), control2: CGPoint(x: 665, y: 414))
        path.addCurve(to: CGPoint(x: 600, y: 562), control1: CGPoint(x: 698, y: 485), control2: CGPoint(x: 657, y: 521))
        path.addCurve(to: CGPoint(x: 436, y: 700), control1: CGPoint(x: 548, y: 603), control2: CGPoint(x: 482, y: 651))
        path.addCurve(to: CGPoint(x: 410, y: 796), control1: CGPoint(x: 400, y: 741), control2: CGPoint(x: 392, y: 774))
        path.addCurve(to: CGPoint(x: 560, y: 865), control1: CGPoint(x: 421, y: 844), control2: CGPoint(x: 485, y: 865))
        path.addCurve(to: CGPoint(x: 928, y: 780), control1: CGPoint(x: 692, y: 872), control2: CGPoint(x: 834, y: 824))
        return path
    }

    private static func makeUpperTail() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 110, y: 570))
        path.addCurve(to: CGPoint(x: 520, y: 428), control1: CGPoint(x: 252, y: 468), control2: CGPoint(x: 402, y: 414))
        return path
    }

    private static func makeMainSweep() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 520, y: 428))
        path.addCurve(to: CGPoint(x: 680, y: 452), control1: CGPoint(x: 610, y: 420), control2: CGPoint(x: 665, y: 414))
        path.addCurve(to: CGPoint(x: 600, y: 562), control1: CGPoint(x: 698, y: 485), control2: CGPoint(x: 657, y: 521))
        path.addCurve(to: CGPoint(x: 436, y: 700), control1: CGPoint(x: 548, y: 603), control2: CGPoint(x: 482, y: 651))
        path.addCurve(to: CGPoint(x: 410, y: 796), control1: CGPoint(x: 400, y: 741), control2: CGPoint(x: 392, y: 774))
        return path
    }

    private static func makeLowerBend() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 410, y: 796))
        path.addCurve(to: CGPoint(x: 560, y: 865), control1: CGPoint(x: 421, y: 844), control2: CGPoint(x: 485, y: 865))
        return path
    }

    private static func makeLowerTail() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 554, y: 864))
        path.addCurve(to: CGPoint(x: 928, y: 780), control1: CGPoint(x: 692, y: 872), control2: CGPoint(x: 834, y: 824))
        return path
    }
}
