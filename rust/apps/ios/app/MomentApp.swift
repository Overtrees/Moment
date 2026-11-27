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
    @Published var height: CGFloat = 24
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
    var fileId: String? {
        (node["attrs"] as? [String: Any])?["fileId"] as? String
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
        case "tip": return "提示"
        case "warning": return "警告"
        case "important": return "重要"
        case "caution": return "警示"
        default: return "注意"
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
    /// 新指令 forceSafeMode，S13）。
    case safe(streak: Int, step: String, source: String)
}

// ── 库门面 ──────────────────────────────────────────
final class Library: ObservableObject {
    @Published var memos: [MemoItem] = []
    @Published var timing = "启动中…"
    @Published var searchHits: [String]? = nil
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
        var s = LaunchSentinelStore.load()
        s.busy = true
        s.step = step
        if !LaunchSentinelStore.save(s) {
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
        // launchSuspend 清除，不误报。streak 清零。
        var s = LaunchSentinelStore.load()
        s.streak = 0
        LaunchSentinelStore.save(s)
        launchMark(LaunchStep.session)
    }

    /// 场景标记（首页/编辑页出现时更新哨兵步骤，
    /// 崩溃留痕能定位到场景）。哨兵未置时不动。
    static func markScene(_ scene: String) {
        var s = LaunchSentinelStore.load()
        guard s.busy else { return }
        s.step = scene
        LaunchSentinelStore.save(s)
    }

    /// 正常退后台：清哨兵（不算未收尾）。
    static func launchSuspend() {
        var s = LaunchSentinelStore.load()
        s.busy = false
        LaunchSentinelStore.save(s)
    }

    /// 从后台回前台：续上哨兵（若已清）。
    static func launchResume() {
        var s = LaunchSentinelStore.load()
        if !s.busy {
            s.busy = true
            s.step = LaunchStep.session
            LaunchSentinelStore.save(s)
        }
    }

    private func launchFailed() {
        var s = LaunchSentinelStore.load()
        s.busy = false
        LaunchSentinelStore.save(s)
    }

    /// S6：救援动作跨启动留痕（RescueView 各动作调
    /// 用）：写哨兵 lastRescueAction，下次启动 LAUNCH
    /// 行尾附 lastRescue=。R3 起同步给快照环打标
    /// （S5 折行面：下次启动 RESCUE log 行的来源）。
    static func recordRescueAction(_ action: String) {
        var s = LaunchSentinelStore.load()
        s.lastRescueAction = action
        s.lastRescueAt = Date().timeIntervalSince1970
        LaunchSentinelStore.save(s)
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

    /// 只读副本目录（tmp 域；退出/重进时可删）。
    private func readOnlyCopyDir() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moment-rescue-ro").path
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
    // 只管「活着但挂住」：load() 起点 arm、didLoad
    // （成功/失败两路）即取消；进程已死由 S2 哨兵
    // 在下次启动管。OPS 可点名禁用本步（热修面：
    // 浮条自身异常时远程关停，步名 OpsStep.watchdog
    // 已在 MomentOps 登记）。
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

    /// 上次启动判定（S2，init 内同步执行）：停在加
    /// 载步 = 启动期死亡，streak+1 落盘；≥2 进安全
    /// 模式、≥3 沿用 notice、==1 本次成功后提示一
    /// 次。停在会话/场景/首帧步 = 前台终止，warn 留
    /// 痕不计数、永不触发安全模式。判定同时读热更
    /// 新指令缓存（S13）：forceSafeMode 在位直接进
    /// 安全模式（来源标 ops）。LAUNCH 行在此记（行
    /// 文沿旧格式 + 附 lastRescue）。
    private func judgePreviousLaunch() {
        bootAppliedOps = OpsDirectives.cached()
        var s = LaunchSentinelStore.load()
        if s.busy {
            let prevStep = s.step.isEmpty ? "?" : s.step
            let rescueSuffix = s.lastRescueAction.isEmpty
                ? "" : " lastRescue=\(s.lastRescueAction)"
            if LaunchStep.isLoadStep(prevStep) {
                s.streak += 1
                prevLaunchStep = prevStep
                prevLaunchStreak = s.streak
                LaunchSentinelStore.save(s)
                DiagLog.shared.log(.error,
                    "LAUNCH 上次启动未完成（停在步骤："
                    + "\(prevStep)），连续第 \(s.streak) 次"
                    + rescueSuffix)
                if s.streak >= 3 {
                    notice = Lang.tf(
                        "notice.launch_streak",
                        ["n": "\(s.streak)"])
                }
                if s.streak == 1 {
                    launchOnceNoticePending = true
                }
                if s.streak >= 2 {
                    bootMode = .safe(streak: s.streak,
                                     step: prevStep,
                                     source: "streak")
                }
            } else {
                DiagLog.shared.log(.warn,
                    "LAUNCH 上次会话未正常收尾（停在："
                    + "\(prevStep)），疑似前台崩溃或被系统终止"
                    + rescueSuffix)
            }
        }
        if bootMode == .normal,
           bootAppliedOps.forceSafeMode {
            bootMode = .safe(streak: prevLaunchStreak,
                             step: prevLaunchStep,
                             source: "ops")
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
        DispatchQueue.main.async {
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
    func touchMemos() { memosVersion += 1 }
    func touchManifest() { manifestVersion += 1 }

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
    func stageImport(from picked: URL) -> (Int, Int)? {
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
            try FileManager.default.copyItem(
                at: picked,
                to: URL(fileURLWithPath: pendingImportPath))
            let stats = try lib?.validateBackup(
                zipPath: pendingImportPath) ?? ""
            return Self.parseStats(stats)
        } catch {
            DiagLog.shared.log(.error,
                "导入校验失败: \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.import_failed"),
                detail: "\(error)")
            return nil
        }
    }

    /// 导入第二步：确认后整库替换（校验已过）。
    func commitStagedImport() -> (Int, Int)? {
        if writeBlocked("import") { return nil }
        do {
            let result = try lib?.importBackup(
                zipPath: pendingImportPath) ?? ""
            let stats = Self.parseStats(result)
            recordOp(kind: "import", ok: true,
                     detail: pickedImportName ?? "")
            DiagLog.shared.log(.info, "导入备份 \(result)")
            if let lib { try reload(lib: lib) }
            return stats
        } catch {
            recordOp(kind: "import", ok: false, detail: "")
            DiagLog.shared.log(.error, "导入失败: \(error)")
            ErrBadge.shared.addError(
                Lang.t("errbadge.import_failed"),
                detail: "\(error)")
            return nil
        }
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

    /// 按 fileId 查真实文件名（图片页标题口径）：附
    /// 件清单（manifest）为唯一真值源优先查（Web
    /// att_name_in_manifest 同序），清单无此条目时回
    /// 退扫各备忘块节点里带的名字，都无回 nil。
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

    func search(_ q: String) {
        let query = q.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { searchHits = nil; return }
        guard let lib else {
            searchHits = []
            DiagLog.shared.log(.error,
                "搜索失败（库未打开）")
            ErrBadge.shared.addWarn(
                Lang.t("errbadge.search_failed"))
            return
        }
        do {
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
            searchHits = memos.map(\.id).filter {
                hits.contains($0)
            }
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
        guard let lib else { return nil }
        do {
            let json = try lib.searchIdsJson(query: query)
            let data = json.data(using: .utf8)
            var hits = Set((try? JSONSerialization
                .jsonObject(with: data ?? Data()))
                as? [String] ?? [])
            let needle = query.lowercased()
            for m in memos where !hits.contains(m.id) {
                if Self.searchHaystack(of: m)
                    .contains(needle) {
                    hits.insert(m.id)
                }
            }
            return memos.map(\.id).filter {
                hits.contains($0)
            }
        } catch {
            return nil
        }
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
    static func dynFont(size: CGFloat,
                        weight: UIFont.Weight = .regular,
                        style: UIFont.TextStyle = .body,
                        mono: Bool = false) -> UIFont {
        let base = mono
            ? UIFont.monospacedSystemFont(ofSize: size,
                                          weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style)
            .scaledFont(for: base)
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
        let bg = UIColor(red: 1.0, green: 0.8, blue: 0,
                         alpha: 0.25)
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

    /// 行内代码底（Web --code-bg 实色，动态明暗）。
    static var inlineCodeBg: UIColor {
        UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.173, green: 0.173,
                          blue: 0.180, alpha: 1)
                : UIColor(red: 0.957, green: 0.957,
                          blue: 0.961, alpha: 1)
        }
    }

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

    static func attributed(runs: [[String: Any]],
                           base: UIFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for r in runs {
            let t = r["text"] as? String ?? ""
            if t.isEmpty { continue }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font(base: base,
                            bold: r["bold"] as? Bool ?? false,
                            italic: r["italic"] as? Bool ?? false,
                            code: r["code"] as? Bool ?? false),
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
                    attrs[.font] = UIFont.monospacedSystemFont(
                        ofSize: base.pointSize * 0.85,
                        weight: .regular)
                    attrs[.foregroundColor] = T.mathFailUI
                case .pending:
                    attrs[.font] = UIFont.monospacedSystemFont(
                        ofSize: base.pointSize * 0.85,
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
    /// 跨块方向键导航的模型钩（BlockTextView 注入）：
    /// pressesBegan 先问 EditorModel.handleKey，消费
    /// 则默认光标移动不发生。
    weak var navEditor: EditorModel?
    var navBlockId: String?
    /// 硬件键盘 Shift 按压态（Shift+Enter 软换行判定；
    /// UITextViewDelegate 不带修饰键，只能在按键事件
    /// 层跟踪）。
    private(set) var shiftHeld = false

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
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
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(
            top: 2, left: 0, bottom: 2, right: 0)
        // 链接色（Web --md-link-color #005BBB/#72B7FF，
        // 线 1 #10；系统默认蓝与之不同）。
        tv.linkTextAttributes = [
            .foregroundColor: UIColor { tc in
                tc.userInterfaceStyle == .dark
                    ? UIColor(red: 0.447, green: 0.718,
                              blue: 1.0, alpha: 1)
                    : UIColor(red: 0, green: 0.357,
                              blue: 0.733, alpha: 1)
            },
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        tv.textContainer.lineFragmentPadding = 0
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
        let base = Marks.baseFont(for: block)
        tv.font = base
        tv.typingAttributes = [.font: base]
        if block.type == "quote" {
            tv.textColor = T.quoteTextUI
        }
        tv.attributedText = Marks.withRhythm(
            Marks.attributed(runs: block.runs, base: base),
            block: block)
        applyDoneStyle(tv)
        // 键盘收起的确定性出口：UITextView 是第一响应
        // 者时 SwiftUI 的 .keyboard toolbar 不生效（它
        // 只服务 SwiftUI 文本控件）——改挂 UIKit 的
        // inputAccessoryView「完成」钮，点击即辞焦。
        let bar = UIToolbar()
        bar.sizeToFit()
        let done = UIBarButtonItem(
            title: "完成", style: .done,
            target: tv, action: #selector(
                UIResponder.resignFirstResponder))
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                            target: nil, action: nil),
            done,
        ]
        tv.inputAccessoryView = bar
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
        if abs(h - block.height) > 0.5 {
            DispatchQueue.main.async { block.height = h }
        }
        return CGSize(width: w, height: h)
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
        m.addAttribute(.foregroundColor,
                       value: UIColor { tc in
                           // 完成态文字色（Web --md-text-
                           // muted #626267，线 1 #15）。
                           tc.userInterfaceStyle == .dark
                               ? UIColor(red: 0.706, green: 0.706,
                                         blue: 0.725, alpha: 1)
                               : UIColor(red: 0.384, green: 0.384,
                                         blue: 0.404, alpha: 1)
                       },
                       range: full)
        tv.attributedText = m
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
        // （成功校验 + 有界重试，见其注释）。
        let initialClaim = editor.map {
            $0.wantsInitialFocus && $0.focusGateOpen
                && $0.blocks.first(where: { $0.isText })?.id
                    == block.id
        } ?? false
        if initialClaim, let ed = editor {
            claimInitialFocus(tv, ed: ed)
        } else if let ed = editor,
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
            tv.selectedRange = NSRange(location: caret,
                                       length: 0)
            DispatchQueue.main.async {
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
            tv.selectedRange = NSRange(
                location: min(off, tv.text.count),
                length: 0)
            DispatchQueue.main.async {
                ed.pendingCaretOffset = nil
                if ed.focusBlockId == block.id {
                    ed.focusBlockId = nil
                }
            }
        }
        if (tv.text != block.text || typeChanged)
            && tv.markedTextRange == nil
            && (!tv.isFirstResponder || versionChanged) {
            let base = Marks.baseFont(for: block)
            tv.font = base
            tv.typingAttributes = [.font: base]
            if block.type == "quote" {
                tv.textColor = T.quoteTextUI
            } else {
                tv.textColor = .label
            }
            tv.attributedText = Marks.withRhythm(
                Marks.attributed(runs: block.runs, base: base),
                block: block)
            applyDoneStyle(tv)
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
        /// 已做全量布局的文本签名（内容+宽度）：未变
        /// 则跳过 ensureLayout，防滚动期反复全量布局。
        var laidOutSig = ""
        init(_ p: BlockTextView) { parent = p }

        func textViewDidBeginEditing(_ tv: UITextView) {
            parent.editor?.editingBlockId = parent.block.id
            // 文本编辑会话开始压一帧历史（撤销回到会话始）。
            parent.editor?.pushHistory()
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.editor?.editingBlockId == parent.block.id {
                parent.editor?.editingBlockId = nil
                // 失焦转预览时点补尾随空段（Web 口径）。
                parent.editor?.materializeMdTrails()
            }
        }

        func textView(_ tv: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard let ed = parent.editor,
                  tv.markedTextRange == nil,
                  parent.block.isText
                    || parent.block.type == "list-item"
            else { return true }
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
                    return true  // 代码块内换行是正文
                }
                if text == "\n",
                   (tv as? EditorTextView)?.shiftHeld
                       == true {
                    // Shift+Enter 软换行（Web 口径）：块内
                    // 换行不拆块，放行原生插入。
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
            if let end = tv.position(
                from: tv.beginningOfDocument,
                offset: tv.selectedRange.location
                    + tv.selectedRange.length) {
                caretX = tv.convert(
                    tv.caretRect(for: end), to: nil).minX
            }
            parent.editor?.updateSlash(
                for: parent.block, selUTF16: tv.selectedRange,
                caretX: caretX)
        }
    }
}

// ── 图片块：fileId 走 FFI 附件字节，URL 走网络 ──────
/// 统一解码（用户 2026-11-26 裁定补 GIF 播放）：多
/// 帧图（GIF 等）经 ImageIO 逐帧解码 + 帧时长组装
/// animatedImage（Web <img> 本就播、原生 UIImage
/// (data:) 只取首帧是缺口）；单帧走常规解码。帧时
/// 长取 GIF 的 delay（下限 0.02s 防零时长爆速），无
/// 时长信息时 0.1s/帧。
func decodeImage(_ data: Data) -> UIImage? {
    guard let src = CGImageSourceCreateWithData(
        data as CFData, nil) else { return UIImage(data: data) }
    let count = CGImageSourceGetCount(src)
    guard count > 1 else { return UIImage(data: data) }
    var frames: [UIImage] = []
    var total: TimeInterval = 0
    for i in 0..<count {
        guard let cg = CGImageSourceCreateImageAtIndex(
            src, i, nil) else { continue }
        frames.append(UIImage(cgImage: cg))
        var delay: TimeInterval = 0.1
        if let props = CGImageSourceCopyPropertiesAtIndex(
            src, i, nil) as? [String: Any],
           let gif = props[kCGImagePropertyGIFDictionary
                as String] as? [String: Any] {
            let d = (gif[kCGImagePropertyGIFUnclampedDelayTime
                        as String] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime
                        as String] as? Double)
            if let d, d > 0 { delay = max(d, 0.02) }
        }
        total += delay
    }
    guard frames.count > 1 else { return UIImage(data: data) }
    return UIImage.animatedImage(with: frames,
                                 duration: total)
}

final class ImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var failed = false
    private var started = false

    func load(block: BlockState, library: Library) {
        load(fileId: block.fileId, urlString: block.imageURL,
             library: library)
    }

    func load(fileId: String?, urlString: String?,
              library: Library) {
        guard !started else { return }
        started = true
        if let fid = fileId {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = library.attachmentData(fid)
                let img = decodeImage(data)
                DispatchQueue.main.async {
                    self.image = img
                    self.failed = img == nil
                    // 加载失败结果侧记行（批 C）：附件
                    // 缺失/坏图不再只有空白占位无痕。
                    if img == nil {
                        // 同文去重（G7/G8）：列表滚动可
                        // 批量失败，改投 logErrorOnce 只
                        // 留首行、不进徽章防冲掉真错误。
                        DiagLog.shared.logErrorOnce(
                            "图片加载失败 fid=\(fid) "
                            + "bytes=\(data.count)")
                    }
                }
            }
        } else if let s = urlString, let url = URL(string: s) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap { decodeImage($0) }
                DispatchQueue.main.async {
                    self.image = img
                    self.failed = img == nil
                    if img == nil {
                        DiagLog.shared.logErrorOnce(
                            "图片加载失败 url="
                            + "\(url.host ?? "?")")
                    }
                }
            }.resume()
        } else {
            failed = true
        }
    }
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
            if sv.zoomScale < base || sv.zoomScale == 0 {
                sv.zoomScale = base
            }
            center(in: sv, viewport: viewport)
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
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
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
                        library: library)
        }
    }
}

struct ImageBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    /// 拾起态（图本体即视觉面，框挂图上、半径 22）。
    var lifted: Bool = false
    @StateObject private var loader = ImageLoader()

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
                    Text("点击添加图片")
                        .font(.subheadline)
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
                // 限高 668 内 contain。
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: img.size.width,
                           maxHeight: 668)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.cardS))
                    .background {
                        if lifted {
                            LiftFrame(faceRadius: Radius.cardS)
                        }
                    }
                    .frame(maxWidth: .infinity)
            } else if loader.failed {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("图片不可用")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .onAppear { loader.load(block: block, library: library) }
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

    func makeUIViewController(
        context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
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
    /// 口径，批 K F4）；其余调用点（导出面）不传、
    /// 行为不变。
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

// ── 诊断日志管线（Web 口径：300 行环 + 落盘持久 +
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
                                    .font(.system(
                                        size: 12,
                                        weight: .bold))
                                Text(badge.entries.count > 99
                                    ? "99+"
                                    : "\(badge.entries.count)")
                                    .font(.system(
                                        size: 10,
                                        weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                badge.hasError
                                    ? T.dangerBright
                                    : T.warning,
                                in: RoundedRectangle(
                                    cornerRadius: 18))
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
                    .font(.system(size: 13, weight: .bold))
                    // ERROR 标题色 = --color-danger-
                    // light（J2-F29）；徽章底与条目图标
                    // 仍用 dangerBright，不随此改。
                    .foregroundStyle(badge.hasError
                        ? T.dangerLight : T.warning)
                Spacer()
                Button(Lang.t("errbadge.clear")) {
                    badge.clear()
                }
                    .font(.system(size: 11))
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
                                .font(.system(size: 14))
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
                                    .font(.system(
                                        size: 12,
                                        weight: .semibold))
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
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    T.textSecondary)
                                // 堆栈块（Web eb-entry-
                                // stack：9 号等宽、次级
                                // 色、行高 1.4；批 K F5）。
                                if !e.detail.isEmpty {
                                    Text(e.detail)
                                        .font(.system(
                                            size: 9,
                                            design: .monospaced))
                                        .foregroundStyle(
                                            T.textSecondary)
                                        .lineSpacing(9 * 0.4)
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
        .overlayCard(radius: 20)
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
            try? data.write(to: URL(fileURLWithPath: path))
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
        if today.count > 300 {
            today.removeFirst(today.count - 300)
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
                                    .font(.system(
                                        size: 16,
                                        weight: .semibold))
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
                            .font(.system(size: 11))
                            .lineSpacing(5)
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
                                    .font(.system(
                                        size: 16,
                                        weight: .semibold))
                                    .foregroundStyle(T.textMain)
                                Spacer()
                                Text(levelName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(
                                        T.textSecondary)
                                Text("›")
                                    .font(.system(size: 18))
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
                    .glassCard(radius: 28)

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
                        .font(.system(size: 11,
                                      design: .monospaced))
                        .lineSpacing(6)
                        .foregroundStyle(
                            Color(red: 124 / 255,
                                  green: 252 / 255,
                                  blue: 154 / 255))
                        .padding(12)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .background(
                            Color(red: 17 / 255,
                                  green: 17 / 255,
                                  blue: 17 / 255),
                            in: RoundedRectangle(
                                cornerRadius: 28))
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
                                .font(.system(size: 14,
                                               weight: .semibold))
                            Text(Lang.t("diag.export_all"))
                                .font(.system(size: 14,
                                               weight: .semibold))
                            Spacer()
                            Text(Lang.t("diag.export_all_sub"))
                                .font(.system(size: 12))
                                .foregroundStyle(T.textSecondary)
                        }
                        .foregroundStyle(T.textMain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .glassCard(radius: 20)
                    .padding(.top, 12)

                    SectionHeader(
                        text: Lang.t("diag.history"))
                    if diag.archives.isEmpty {
                        Text(Lang.t("diag.empty"))
                            .font(.system(size: 12))
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
                                        .font(.system(size: 13))
                                        .foregroundStyle(T.textMain)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .glassControl(radius: 999)
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
                            .font(.system(size: 13,
                                          weight: .semibold))
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
                            .font(.system(size: 13,
                                          weight: .semibold))
                            .foregroundStyle(T.accent)
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(16)
                    .glassCard(radius: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 126)
                .padding(.bottom, 40)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.textSecondary)
                .frame(width: 44, alignment: .leading)
            Text(v)
                .font(.system(size: 12, design: .monospaced))
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
                            .font(.system(
                                size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity,
                                   alignment: .center)
                    } else {
                        ForEach(Array(lines.enumerated()),
                                id: \.offset) { _, e in
                            Text(e.line)
                                .font(.system(
                                    size: 11,
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
            .foregroundStyle(Color(red: 124 / 255,
                                    green: 252 / 255,
                                    blue: 154 / 255))
            .background(Color(red: 17 / 255, green: 17 / 255,
                              blue: 17 / 255),
                        in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 20)
            .padding(.top, 126)
            // 卡底距（S7）：Web .page-content 底
            // padding = calc(40px + safe)——卡下缘距
            // 视口底 40 + 安全区。此前写死 16、未叠
            // 安全区，卡底几乎贴屏底。
            .padding(.bottom,
                     40 + geo.safeAreaInsets.bottom)
            HStack(alignment: .top) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
                Spacer()
                CompactTitle(text: fileName)
                    .padding(.top, 4)
                Spacer()
                Button(action: exportAll) {
                    // 文字胶囊「导出」（G2）：高 46、
                    // 内距横 18、radius 999、14px
                    // medium、glass-control 面。
                    Text(Lang.t("diag.export"))
                        .font(.system(size: 14,
                                      weight: .medium))
                        .foregroundStyle(T.textMain)
                        .padding(.horizontal, 18)
                        .frame(height: 46)
                        .glassControl(radius: 999)
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(block.itemStates.enumerated()),
                    id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(marker(i))
                            .font(.system(size: 16))
                            .foregroundStyle(T.textMain)
                            .frame(width: 20,
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
                            // ol 1.4em，线 1 #29）。
                            .padding(.leading,
                                     nl.type == "numbered-list"
                                        ? 22 : 19)
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
// 标题/副标题取 zh-CN 语言包定稿，kw/py 为过滤全集） ──
struct SlashCmd {
    var act: String
    var oid: String
    /// 原版 type（过滤 haystack 一员，Web render.rs
    /// SLASH_CMDS.ty 逐项对表）。
    var ty: String
    var icon: String
    var title: String
    var sub: String
    var shortcut: String
    var group: Int  // 0 基础、1 媒体
    var kw: String
    var py: String
}

enum SlashCmds {
    static let all: [SlashCmd] = [
        .init(act: "heading1", oid: "heading", ty: "heading", icon: "textformat.size", title: "标题 1", sub: "一级标题", shortcut: "# ", group: 0, kw: "h1 heading 标题 一级", py: "bt1"),
        .init(act: "heading2", oid: "heading2", ty: "heading", icon: "textformat.size", title: "标题 2", sub: "二级标题", shortcut: "## ", group: 0, kw: "h2 heading2 标题 二级", py: "bt2"),
        .init(act: "heading3", oid: "heading3", ty: "heading", icon: "textformat.size", title: "标题 3", sub: "三级标题", shortcut: "### ", group: 0, kw: "h3 heading3 标题 三级", py: "bt3"),
        .init(act: "paragraph", oid: "paragraph", ty: "paragraph", icon: "text.alignleft", title: "文本", sub: "普通段落", shortcut: "", group: 0, kw: "p paragraph 文本", py: "wb"),
        .init(act: "quote", oid: "quote", ty: "quote", icon: "quote.opening", title: "引用", sub: "引用块", shortcut: "> ", group: 0, kw: "q quote 引用", py: "yy"),
        .init(act: "todo", oid: "todo", ty: "todo", icon: "checklist", title: "待办", sub: "任务清单", shortcut: "[ ] ", group: 0, kw: "t todo 待办", py: "db"),
        .init(act: "divider", oid: "divider", ty: "divider", icon: "minus", title: "分割线", sub: "插入分隔符", shortcut: "---", group: 0, kw: "d divider 分割线", py: "fgx"),
        .init(act: "bold", oid: "bold", ty: "inline_bold", icon: "bold", title: "加粗", sub: "包裹选中文字为 **粗体**", shortcut: "** **", group: 0, kw: "b bold 加粗 粗体", py: "jc"),
        .init(act: "italic", oid: "italic", ty: "inline_italic", icon: "italic", title: "斜体", sub: "包裹选中文字为 *斜体*", shortcut: "* *", group: 0, kw: "i italic 斜体 倾斜", py: "xt"),
        .init(act: "highlight", oid: "highlight", ty: "inline_highlight", icon: "highlighter", title: "高亮", sub: "包裹选中文字为 ==高亮==", shortcut: "== ==", group: 0, kw: "h highlight 高亮", py: "gl"),
        .init(act: "codeBlock", oid: "codeBlock", ty: "code_block", icon: "chevron.left.forwardslash.chevron.right", title: "代码块", sub: "插入代码块", shortcut: "```", group: 0, kw: "code codeblock 代码块", py: "dmk"),
        .init(act: "mathBlock", oid: "mathBlock", ty: "math_block", icon: "sum", title: "公式块", sub: "插入 $$ 公式块", shortcut: "$$", group: 0, kw: "math formula block 公式块", py: "gsk"),
        .init(act: "bulletList", oid: "unorderedList", ty: "unordered_list", icon: "list.bullet", title: "无序列表", sub: "转为 - 列表项", shortcut: "- ", group: 0, kw: "list ul 无序列表 列表", py: "wxl"),
        .init(act: "numberList", oid: "orderedList", ty: "ordered_list", icon: "list.number", title: "有序列表", sub: "转为 1. 列表项", shortcut: "1. ", group: 0, kw: "ol list 有序列表 列表", py: "yxl"),
        .init(act: "callout", oid: "callout", ty: "callout", icon: "exclamationmark.bubble", title: "Callout", sub: "插入 >[!NOTE] 提示卡片", shortcut: "> [!]", group: 0, kw: "callout note tip warning 提示 警告", py: "callout"),
        .init(act: "link", oid: "link", ty: "inline_link", icon: "link", title: "链接", sub: "选中文字转超链接", shortcut: "[](url)", group: 0, kw: "l link 链接 超链接", py: "lj"),
        .init(act: "code", oid: "code", ty: "inline_code", icon: "chevron.left.forwardslash.chevron.right", title: "代码", sub: "内联代码包裹", shortcut: "` `", group: 0, kw: "c code 代码 内联", py: "dm"),
        .init(act: "mathInline", oid: "mathInline", ty: "inline_math", icon: "function", title: "行内公式", sub: "包裹选中文字为 $公式$", shortcut: "$ $", group: 0, kw: "math formula inline 公式 行内", py: "gs"),
        .init(act: "strikethrough", oid: "strikethrough", ty: "inline_strike", icon: "strikethrough", title: "删除线", sub: "包裹选中文字为 ~~删除线~~", shortcut: "~~ ~~", group: 0, kw: "s strike strikethrough 删除线", py: "scx"),
        .init(act: "imgTextCard", oid: "imgTextCard", ty: "imgTextCard", icon: "doc.richtext", title: "图文卡片", sub: "圆角上图下文卡片", shortcut: "", group: 1, kw: "image text card 图文 卡片", py: "twkp"),
        .init(act: "imageTextRow", oid: "imageTextRow", ty: "imageTextRow", icon: "rectangle.split.2x1", title: "图文混排", sub: "图片文字左右并排", shortcut: "", group: 1, kw: "image text row 图文 混排 左右", py: "twhp"),
        .init(act: "musicCard", oid: "musicCard", ty: "musicCard", icon: "music.note", title: "音乐卡片", sub: "插入音乐链接卡片", shortcut: "", group: 1, kw: "m music 音乐 卡片", py: "yykp"),
        .init(act: "image", oid: "image", ty: "image", icon: "photo", title: "图片", sub: "插入图片占位", shortcut: "", group: 1, kw: "i image 图片", py: "tp"),
        .init(act: "gallery", oid: "gallery", ty: "gallery", icon: "photo.on.rectangle.angled", title: "画廊", sub: "插入多图画廊", shortcut: "", group: 1, kw: "g gallery 画廊", py: "hl"),
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
    // 菜单覆盖的原子块类型（Web CARD_MENU_TYPES）；
    // 其中可进编辑态/有编辑动作的为 editCardTypes
    // （Web has_edit 名单），musicCard 的「编辑」是即时
    // 输 URL 动作、不设持续编辑态。
    static let cardMenuTypes: Set<String> = [
        "imgTextCard", "imageTextRow", "image", "gallery",
        "musicCard", "link-card", "attachment", "video",
        "divider",
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
    let item: MemoItem
    let library: Library
    private var saveWork: DispatchWorkItem?

    // 撤销/重做历史栈（Web 口径）：doc 快照（flushed
    // 节点 + 标题），结构操作与文本编辑会话开始时压栈。
    private var undoStack: [[String: Any]] = []
    private var redoStack: [[String: Any]] = []
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

    static func isAtomicType(_ t: String) -> Bool {
        ["image", "gallery", "video", "musicCard", "link-card",
         "attachment", "imgTextCard", "imageTextRow",
         "divider"].contains(t)
    }

    init(item: MemoItem, library: Library) {
        self.item = item
        self.library = library
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
        // 原子块收尾时物化尾随空段（Web 口径）：末尾恒有
        // 可落焦的文本段，不必点原子块才能续写。
        if let last = blocks.last,
           Self.isAtomicType(last.type) {
            blocks.append(BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "paragraph",
                "children": [["text": ""]],
            ]))
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
        block.mdCacheText = block.text
        block.mdCacheKind = kind
        block.mdCacheBlocks = []
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
        let atomicNext: Set<String> = [
            "image", "gallery", "imgTextCard", "imageTextRow",
            "attachment", "link-card", "musicCard",
            "embedCard", "divider",
        ]
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
                    need = atomicNext.contains(next.type)
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

    func pushHistory() {
        undoStack.append(snapshot())
        if undoStack.count > 50 {
            undoStack.removeFirst(
                undoStack.count - 50)
        }
        redoStack.removeAll()
        syncHistoryFlags()
    }

    private func syncHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
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

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT undo 余栈 undo=\(undoStack.count) "
            + "redo=\(redoStack.count)")
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        applySnapshot(s)
        syncHistoryFlags()
        DiagLog.shared.log(.info,
            "EDIT redo 余栈 undo=\(undoStack.count) "
            + "redo=\(redoStack.count)")
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

    func setBlockType(_ b: BlockState, type: String,
                      level: Int = 2) {
        pushHistory()
        var n = b.node
        n["type"] = type
        var attrs = n["attrs"] as? [String: Any] ?? [:]
        if type == "heading" { attrs["level"] = level }
        if type == "todo" && attrs["checked"] == nil {
            attrs["checked"] = false
            b.checked = false
        }
        n["attrs"] = attrs
        b.node = n
        b.nodeVersion += 1
        scheduleSave()
        DiagLog.shared.log(.info,
            "EDIT convert \(b.id) -> \(type)"
            + (type == "heading" ? " level=\(level)" : ""))
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
        blocks.removeAll { $0.id == b.id }
        if blocks.isEmpty {
            blocks.append(BlockState(node: [
                "id": "b-" + UUID().uuidString.prefix(8)
                    .lowercased(),
                "type": "paragraph",
                "children": [["text": ""]],
            ]))
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
    /// 为列表块时并入其末项（T-13）。
    func mergeBlockBackward(_ b: BlockState) {
        guard let i = blocks.firstIndex(
            where: { $0.id == b.id }), i > 0 else { return }
        let prev = blocks[i - 1]
        if b.text.isEmpty {
            guard let target = nearestTextBlock(before: i)
            else { return }
            pushHistory()
            blocks.remove(at: i)
            focusBlockId = target.id
            focusCaretEnd = true
            DiagLog.shared.log(.info,
                "EDIT merge empty \(b.id) -> \(target.id)")
        } else if prev.isText {
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
            return
        }
        scheduleSave()
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

    private func tvForBlock(_ id: String) -> EditorTextView? {
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
    /// typographicBounds + 容器内距。
    private struct LineBox {
        var range: NSRange
        var rect: CGRect
    }

    private func lineBoxes(_ tv: EditorTextView)
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
    private func hitOffset(tv: EditorTextView, line: LineBox,
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
                     caretX: CGFloat? = nil) {
        let eligible = (block.isText
            || block.type == "list-item")
            && block.type != "codeBlock"
            && block.type != "callout"
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
        // URL 抑制：token 前是 : 或 /（scheme 内斜杠），
        // 或所在词以 www./http 起头。
        if ts > 0 && (chars[ts - 1] == ":"
            || chars[ts - 1] == "/") {
            close()
            return
        }
        var wordStart = ts
        while wordStart > 0 && chars[wordStart - 1] != " "
            && chars[wordStart - 1] != "\n" {
            wordStart -= 1
        }
        let word = String(chars[wordStart..<caret])
        if word.hasPrefix("www.") || word.hasPrefix("http") {
            close()
            return
        }
        let query = String(chars[(ts + 1)..<caret])
        guard query.count <= 30 else { close(); return }
        if let caretX { slashAnchorX = caretX }
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

    /// token 剥离后的选区修正（Web applyInline 偏移口径）。
    private func adjustedSel() -> (Int, Int) {
        var s = slashSelStart
        var l = slashSelLen
        let ts = slashTokenStart
        let te = slashTokenStart + slashTokenLen
        if s >= te {
            s -= slashTokenLen
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
        removeRunRange(b, start: slashTokenStart,
                       len: slashTokenLen)
        var (s, l) = adjustedSel()
        (s, l) = trimmedSel(b, s, l)
        if act == "link" {
            linkSelStart = s
            linkSelLen = l
            linkTokenStart = slashTokenStart
            linkFormBlockId = b.id
            return
        }
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
        // 时记录（Web 口径）。
        if act != "link" {
            slashBlockId = nil
            SlashCmds.recordRecent(act)
        }
        pushHistory()
        let inlineActs: Set<String> = [
            "bold", "italic", "code", "strikethrough",
            "highlight", "link", "mathInline",
        ]
        if inlineActs.contains(act) {
            applyInlineSlash(act, on: target)
            scheduleSave()
            DiagLog.shared.log(.info,
                "EDIT slash \(act) \(target.id)")
            return
        }
        removeRunRange(target, start: slashTokenStart,
                       len: slashTokenLen)
        var b = target
        if let list = parentList {
            b = promoteListItem(list: list, item: target)
        }
        func convert(_ type: String,
                     level: Int? = nil) {
            var n = b.node
            n["type"] = type
            n["children"] = BlockState.childrenFrom(
                runs: b.runs)
            var attrs = n["attrs"] as? [String: Any] ?? [:]
            if let level {
                attrs["level"] = level
            }
            if type == "todo" {
                attrs["checked"] = false
            }
            n["attrs"] = attrs.isEmpty ? nil : attrs
            if type == "callout" {
                n["calloutType"] = "note"
            }
            b.node = n
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
        case "todo": convert("todo")
        case "codeBlock": convert("codeBlock")
        case "mathBlock":
            // 公式块（原生增强，原版无）：内容置 $$
            // 围栏三行（首/尾行 $$、中行空）后走段落
            // 转换落盘（MD 公式无独立块型，段落即其
            // 落盘形态）；失焦预览经 core 切分，独占
            // 段成块级公式（md.rs 独占段 Math 分支）。
            // 光标落中间空行（偏移 3），尾段统一落点
            // 不覆盖（已入下方排除名单）。
            b.runs = [["text": "$$\n\n$$"]]
            convert("paragraph")
            focusBlockId = b.id
            focusCaretEnd = false
            pendingCaretOffset = 3
        case "callout": convert("callout")
        case "divider":
            b.node = ["id": b.id, "type": "divider"]
            b.nodeVersion += 1
            let p = trailingParagraph(after: b)
            focusBlockId = p.id
            focusCaretEnd = false
        case "bulletList", "numberList":
            let item = BlockState(node: [
                "id": "b-" + UUID().uuidString
                    .prefix(8).lowercased(),
                "type": "list-item",
                "children": BlockState.childrenFrom(
                    runs: b.runs),
            ])
            item.runs = b.runs
            item.text = b.text
            b.node = [
                "id": b.id,
                "type": act == "bulletList"
                    ? "bulleted-list" : "numbered-list",
                "children": [],
            ]
            b.itemStates = [item]
            b.nodeVersion += 1
            focusBlockId = item.id
            focusCaretEnd = false
            pendingCaretOffset = min(slashTokenStart,
                                     item.text.count)
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
        guard trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://") else { return false }
        linkFormBlockId = nil
        slashBlockId = nil
        SlashCmds.recordRecent("link")
        pushHistory()
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
            } else if li > 0, blocks[li - 1].isText {
                // 非空首项 + 前为文本块：并入前块末
                // 尾，光标落接合处。
                let prev = blocks[li - 1]
                pushHistory()
                let junction = prev.text.count
                prev.runs = prev.runs + item.runs
                prev.text = prev.text + item.text
                prev.nodeVersion += 1
                list.itemStates.remove(at: 0)
                if list.itemStates.isEmpty {
                    blocks.remove(at: li)
                }
                focusBlockId = prev.id
                focusCaretEnd = false
                pendingCaretOffset = junction
            } else {
                // 前为原子块或无前块：不删不提（Web 原
                // 子规则/无 prev 无动作）。
                return
            }
            list.nodeVersion += 1
            scheduleSave()
            let mergeCase = item.text.isEmpty
                ? "first-empty" : "first-merge"
            DiagLog.shared.log(.info,
                "EDIT merge list-item \(item.id) "
                + "case=\(mergeCase)")
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
        // 步，未做）；单栏时不钳制。
        if columnsActive, blocks.count > 1 {
            let b = columnBoundaryIndex
            if from < b {
                to = min(to, b - 1)
            } else {
                to = max(to, b)
            }
        }
        if to != from {
            pushHistory()
            let moved = blocks.remove(at: from)
            blocks.insert(moved, at: to)
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
        return cleaned.isEmpty ? "无标题" : cleaned
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
                ErrBadge.shared.addError("PDF 导出失败")
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
            .alert("编辑链接", isPresented: Binding(
                get: { ui.musicEditBlockId != nil },
                set: { if !$0 { ui.musicEditBlockId = nil } })) {
                TextField("https://…", text: Binding(
                    get: { ui.musicURLDraft },
                    set: { ui.musicURLDraft = $0 }))
                Button("取消", role: .cancel) {}
                Button("保存") {
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

    /// 卡片类块（Web CARD_MENU_TYPES）：0.9.49 起与
    /// 文本块同走按压引擎拾起（Web pickup 对全部块
    /// 单元一视同仁、原子块全可拖、卡菜单骑拾起；
    /// 用户 2026-11-27 纠正口径）——本判定现只决定
    /// 拾起后骑哪套菜单（卡菜单 cardMenuBlockId vs
    /// 类型转换菜单 blockMenuBlockId），不再决定武
    /// 装与否。此前「卡片不参与拖拽、菜单优先」是
    /// 0.9.19 的范围裁剪、非 Web 口径，已废；其独
    /// 立 SwiftUI 长按（CardMenuGesture）同轮退役。
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
                    editor.pushHistory()
                    block.checked.toggle()
                    var n = block.node
                    var attrs = n["attrs"] as? [String: Any]
                        ?? [:]
                    attrs["checked"] = block.checked
                    n["attrs"] = attrs
                    block.node = n
                    block.nodeVersion += 1
                    editor.scheduleSave()
                } label: {
                    Image(systemName: block.checked
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.system(size: 22))
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
                            editor.imageTarget = ImageTarget(
                                fileId: block.fileId,
                                urlString: block.imageURL,
                                name: block.node["name"] as? String
                                    ?? "图片")
                        }
                    }
            } else if block.type == "gallery" {
                // Web 口径：图库左右内缩 36（与图片块
                // 同）；宽屏（双栏）下 Web 取消内缩。
                GalleryBlockView(block: block, editor: editor)
                    .padding(.horizontal,
                             editor.columnsActive ? 0 : 36)
            } else if block.type == "musicCard",
                      (block.node["status"] as? String)
                        == "input" {
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
                            .font(.system(size: 18,
                                          weight: .semibold))
                            .foregroundStyle(
                                block.calloutAccent)
                        Text(block.calloutTitle)
                            .font(.system(size: 15,
                                          weight: .bold))
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
                    .font(.system(size: 14))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.vertical, 2)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                    Text("\(block.type) 块 · 后续轮支持")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
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
            // 原子块实测高回报（拖拽落点累加用；文本块由
            // UITextView recalc 回报）。块顶位置一并回报
            // （斜杠面板锚定；非 Published 不触发重演算）。
            Color.clear
                .onAppear {
                    if !block.isText {
                        block.height = geo.size.height
                    }
                    block.rowW = geo.size.width
                    block.frameMinY = geo.frame(
                        in: .named("editorScroll")).minY
                    block.frameMinX = geo.frame(
                        in: .named("editorScroll")).minX
                }
                .onChange(of: geo.size.height) { h in
                    if !block.isText { block.height = h }
                }
                .onChange(of: geo.size.width) { w in
                    block.rowW = w
                }
                .onChange(of: geo.frame(
                    in: .named("editorScroll")).minY) { y in
                    block.frameMinY = y
                }
                .onChange(of: geo.frame(
                    in: .named("editorScroll")).minX) { x in
                    block.frameMinX = x
                }
        })
        .background(DragPressAnchor(
            blockId: block.id,
            enabled: dragAllowed,
            onPickup: {
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
            },
            onDrag: { dy in
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
            },
            onDrop: {
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
            },
            onCancel: {
                if editor.draggingId == block.id {
                    editor.draggingId = nil
                    editor.dragDy = 0
                }
            }))
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
            // 无条件复位拖拽态，防 draggingId 残留锁死
            // 全篇拾起（三线审计定案）。
            if editor.draggingId == block.id {
                editor.draggingId = nil
                editor.dragDy = 0
            }
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
    private var liftFaceRadius: CGFloat? {
        switch block.type {
        case "quote": return Radius.quote
        case "callout", "codeBlock": return Radius.block
        case "imgTextCard", "imageTextRow":
            return Radius.cardS
        case "video": return Radius.cardS
        case "link-card":
            return block.fileId != nil
                ? attachmentLiftFace : Radius.cardL
        case "musicCard": return musicLiftFace
        case "attachment": return attachmentLiftFace
        case "image":
            // 面恒在子视图内（图本体 cardS / 空占位
            // 面 cardL 各挂各的 LiftFrame），行级恒不
            // 出框（fix_lift_spacing.md）。
            return nil
        case "gallery": return nil
        default: return 0
        }
    }

    /// 音乐卡拾起面：与呈现分支序同判据（BlockRow
    /// 分发 status==input → MusicPillView 胶囊；余下
    /// CardBlockView 分支序：fileId → 文件行面、
    /// loading/error/ready → 内容卡、url 丸 → 胶
    /// 囊、无面 → 0）。
    private var musicLiftFace: CGFloat {
        if block.fileId != nil { return attachmentLiftFace }
        let status = block.node["status"] as? String ?? ""
        if status == "input" { return Radius.pill }
        if status == "loading" { return Radius.cardL }
        let url = block.node["url"] as? String ?? ""
        if status == "error" && !url.isEmpty {
            return Radius.cardL
        }
        let meta = block.node["meta"] as? [String: Any]
        let title = (meta?["title"] as? String) ?? ""
        if !title.isEmpty { return Radius.cardL }
        if !url.isEmpty { return Radius.pill }
        return 0
    }

    /// 附件拾起面：与 AttachmentBlockView 同判据
    /// ——单图附件（node.image && files.count == 1，
    /// files 口径与原视图一致：items 中带 fileId 者
    /// 计数、无 items 时 attrs.fileId 兜底一件）为
    /// 图片面（cardL 裁切）；文件行为 AttachmentRow
    /// （半径恒 cardL，与行同源，S1 裁断）。
    private var attachmentLiftFace: CGFloat {
        let attrs = block.node["attrs"] as? [String: Any]
        let isImage = (block.node["image"] as? Bool) == true
        var fileCount = 0
        if let items = attrs?["items"] as? [[String: Any]] {
            fileCount = items.filter {
                ($0["fileId"] as? String) != nil
            }.count
        } else if block.fileId != nil {
            fileCount = 1
        }
        if isImage && fileCount == 1 { return Radius.cardL }
        return Radius.cardL
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
        if editor.columnsActive, editor.blocks.count > 1 {
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
    /// 剪、非 Web 口径）已废。
    private var dragAllowed: Bool {
        !(block.isText && editor.editingBlockId == block.id)
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
    @Environment(\.dismiss) private var dismiss
    // M30：减弱动态效果时浮层进出场降级瞬时。
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @FocusState private var linkFieldFocused: Bool

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
        /// ••• 菜单内容实测高（面板内 VStack 的
        /// onGeometryChange 回写）：面板高 = 内容高
        /// （上限沿旧 cap）——旧实现 ScrollView 在
        /// ZStack 里被同级 Color.clear 撑到 cap、
        /// 内容悬空（截图四，fix_lift_spacing.md）；
        /// 0 = 尚未量得，首帧走构成估高。
        @Published var menuPanelH: CGFloat = 0
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
            // 藏态仍每轮 body 全量重构。预建时点见
            // onAppear（落定后），窗内抢先打开由 showMenu
            // 的 onChange 兜底即时建（首开无进场动画、
            // 其后与旧口径一致）。
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
        .onChange(of: ui.showMenu) { open in
            // 菜单惰性构建的抢先兜底：预建时点（落定后
            // 0.6s）未到就打开，立即建整树。
            if open && !ui.menuBuilt { ui.menuBuilt = true }
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
                    // 底距落定应用（0.9.48）：动画期逐
                    // 帧值只记 safeBottom，kbPad 去抖后
                    // 一次生效、不逐帧重排内容。
                    ui.settleKbPad(sb)
                }
        })
        .toolbar {
            // 键盘收起的确定性出口（系统口径）：滚动交
            // 互收起之外，键盘上方工具栏再给一枚「完成」。
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder
                            .resignFirstResponder),
                        to: nil, from: nil, for: nil)
                }
            }
        }
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
            // 菜单整树惰性预建：转场窗（0.35s）与
            // settle 打点窗（0.5s）都过后才建，稳态
            // 打开的进出场动画口径不变。
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.6) {
                if !ui.menuBuilt { ui.menuBuilt = true }
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
                + 168 + 220 + 40
            DiagLog.shared.log(.info,
                "SCROLL close maxY=\(Int(editor.scrollState.maxScrollY)) "
                + "estContentH=\(Int(estH)) "
                + "viewH=\(Int(ui.viewH)) "
                + "heights=\(editor.blocks.map { Int($0.height) })")
            editor.saveNow()
        }
        .animation(.easeOut(duration: 0.18),
                   value: editor.slashBlockId ?? "")
        .confirmationDialog("头像",
            isPresented: Binding(
                get: { ui.showAvatarChoice },
                set: { ui.showAvatarChoice = $0 }),
            titleVisibility: .visible) {
            Button("更换头像") { ui.showAvatarPicker = true }
            Button("恢复默认头像", role: .destructive) {
                editor.library.setAvatar(
                    for: editor.item.id, dataURL: nil)
            }
            Button("取消", role: .cancel) {}
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
            PhotoPicker { data, pname in
                let fid = "att-" + UUID().uuidString
                    .prefix(12).lowercased()
                guard editor.library.putAttachment(
                    fid, data, name: pname) else {
                    DiagLog.shared.log(.error,
                        "选图未成块（附件写入失败）fid=\(fid)")
                    return
                }
                editor.addImageBlock(fileId: fid)
            }
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
        .modifier(CardEditSheets(editor: editor, ui: ui))
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        .confirmationDialog("添加附件",
            isPresented: Binding(
                get: { ui.showAttachChoice },
                set: { ui.showAttachChoice = $0 }),
            titleVisibility: .visible) {
            Button("图片") { ui.showPhotoPicker = true }
            Button("文件") { ui.showFilePicker = true }
            Button("取消", role: .cancel) {}
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
                    editor.addAttachmentBlock(
                        fileId: fid,
                        name: url.lastPathComponent,
                        size: data.count)
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
                + (editor.twoPaneIndependent ? 168 : 0)
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
            let colW = (contentW - 32 - gap) / 2
            x = margin + colW + gap + block.frameMinX
        }
        return min(max(x, 12), max(12, viewW - panelW - 12))
    }

    /// 卡片浮层菜单本体（Web .card-menu-panel：项与
    /// ••• 菜单同 menuItem 度量，浮层档、radius 22）。
    private func cardMenuPanel(block: BlockState?,
                               hasEdit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasEdit, let block {
                menuItem(icon: "pencil", title: "编辑") {
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
                menuItem(icon: "trash", title: "删除此块",
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
        .overlayCard(radius: 22)
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
                + (editor.twoPaneIndependent ? 168 : 0)
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
                             title: "正文") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "paragraph")
                    }
                    menuItem(icon: "textformat.size",
                             title: "标题 1") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 1)
                    }
                    menuItem(icon: "textformat.size",
                             title: "标题 2") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 2)
                    }
                    menuItem(icon: "textformat.size",
                             title: "标题 3") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "heading",
                                            level: 3)
                    }
                    menuItem(icon: "checklist",
                             title: "待办") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "todo")
                    }
                    menuItem(icon: "quote.opening",
                             title: "引用") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "quote")
                    }
                    menuItem(icon: "exclamationmark.bubble",
                             title: "提示") {
                        editor.blockMenuBlockId = nil
                        editor.setBlockType(block,
                                            type: "callout")
                    }
                }
                if let block {
                    menuItem(icon: "trash", title: "删除块",
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
        .overlayCard(radius: 22)
    }

    /// 斜杠/链接面板浮层（从 body 拆出独立计算属性：
    /// EditorView.body 有类型检查超时前科，呈现段一律
    /// 拆出、body 只留一行引用）。锚定触发块（Web
    /// render.rs:651-659 口径）：锚底 + 10 定顶边、放
    /// 不下按实测高上翻、限高随锚位动态收缩（min
    /// (320, 视口 − 顶边 − 16)）。此前按 320 写死估
    /// 高定中心，短列表顶边下移可达约 100px（线 2
    /// #52）。占位账：top = 触发块顶（frameMinY，
    /// independent +168 与卡菜单同口径）；bh = 块
    /// 高；底安全距 12（Web 判翻 vh−8 的既有近似）。
    private var slashLayer: some View {
        GeometryReader { geo in
            let blk = editor.blocks.first {
                $0.id == (editor.linkFormBlockId
                    ?? editor.slashBlockId)
            }
            let top = (blk?.frameMinY ?? 160)
                + (editor.twoPaneIndependent ? 168 : 0)
            let bh = blk?.height ?? 24
            let panelW = slashPanelWidth(
                viewW: geo.size.width)
            let viewH = geo.size.height
            let hRaw = min(
                ui.slashPanelH > 0
                    ? ui.slashPanelH
                    : slashEstimateH(), 320)
            let belowTop = top + bh + 10
            let flipped = belowTop + hRaw > viewH - 12
            let panelTop = flipped
                ? max(12, top - 10 - hRaw) : belowTop
            let maxH = flipped
                ? min(320, max(top - 10 - 12, 48))
                : min(320, viewH - panelTop - 16)
            let h = max(min(hRaw, maxH), 0)
            Group {
                if editor.linkFormBlockId != nil {
                    linkFormPanel
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
        .overlayCard(radius: 22)
    }

    /// 斜杠空态（Web .slash-empty-state 口径，J2-F25）：
    /// 容器 padding 24/12/20、主文 13 次级色、图标
    /// 28 + opacity 0.45 + 下距 8、提示 11 次级色
    /// opacity 0.75 + 上距 8。
    private var slashEmptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(
                    T.textSecondary.opacity(0.45))
                .padding(.bottom, 8)
            Text("未找到匹配命令")
                .font(.system(size: 13))
                .foregroundStyle(T.textSecondary)
            HStack(spacing: 4) {
                Text("试试拼音首字母：")
                slashKbd("bt")
                Text("标题 ·")
                slashKbd("tp")
                Text("图片 ·")
                slashKbd("yykp")
                Text("音乐")
            }
            .font(.system(size: 11))
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
            .font(.system(size: 10, design: .monospaced))
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
            .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 20))
                    .foregroundStyle(T.accent)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        slashHlText(cmd.title, query: query,
                                    size: 14,
                                    weight: .semibold,
                                    color: T.textMain)
                        if recent {
                            // 最近丸（Web .slash-recent-
                            // pill + 面板覆盖口径，J2-F24）：
                            // 字 11、glass-label 色、pad
                            // 2/6、胶囊 glass-control 底 +
                            // 0.5 glass-control 边。
                            Text("最近")
                                .font(.system(size: 11))
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
                                size: 12, weight: .regular,
                                color: T.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                if !cmd.shortcut.isEmpty {
                    Text(cmd.shortcut)
                        .font(.system(size: 11,
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
    private var linkFormPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("链接地址")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
            TextField("https://example.com",
                      text: Binding(
                        get: { ui.linkDraft },
                        set: { ui.linkDraft = $0
                               ui.linkError = false }))
                .font(.system(size: 14))
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
                Text("请输入有效的 http 或 https 链接")
                    .font(.system(size: 12))
                    .foregroundStyle(T.danger)
            }
            HStack(spacing: 8) {
                Spacer()
                // 双钮同规（Web .slash-link-actions 口
                // 径，J2-F27）：字 600 13、min-width 76、
                // min-height 44、padding 0/14、1px 边、
                // radius 999；取消钮边 --border-color，
                // 提交钮边透明（同盒）。
                Button("取消") {
                    // 回命令列表（Web 口径，与 Esc 同）。
                    editor.linkFormBlockId = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.textMain)
                .padding(.horizontal, 14)
                .frame(minWidth: 76, minHeight: 44)
                .background(T.fillHover,
                            in: Capsule())
                .overlay {
                    Capsule().strokeBorder(T.borderSoft,
                                           lineWidth: 1)
                }
                Button("插入链接") { submitLinkForm() }
                    .font(.system(size: 13,
                                  weight: .semibold))
                    .foregroundStyle(.white)
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
        .overlayCard(radius: 22)
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
    @FocusState private var titleFocused: Bool

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

    /// 坞态派生（单点）：滚动紧凑 × 非标题编辑中。
    /// 标题会话期间冻结坞态（Web S7 编辑期抑制翻转
    /// 同口径）——旧实现滚动过 30 即翻转，胶囊在
    /// VStack/HStack 两结构位间重建、字段身份漂移，
    /// 会话可被腰斩。headerOverlay 与 capsuleWidth
    /// 共用此派生，防两处口径漂移。
    private var dockCompact: Bool {
        scroll.scrollY > 30 && !titleFocused
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
        // 紧凑态切换（Web 口径）：0.25s 缓动。动画值在
        // 本视图内读 scrollY，滚动重演算不外溢。
        .animation(.easeInOut(duration: 0.25),
                   value: dockCompact)
    }

private var headerOverlay: some View {
    HStack(alignment: .top, spacing: 0) {
        Button {
            commitTitle()
            editor.saveNow()
            if let onBack { onBack() } else { dismiss() }
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .glassControl(radius: 999)
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
        Button {
            ui.showMenu.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(T.textMain)
                .frame(width: 46, height: 46)
                .glassControl(radius: 999)
        }
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
        ui.titleDraft = ui.titleBase
        titleFocused = false
    }
}

private func commitTitle() {
    // Web 口径：提交时 trim、空回退「无标题」（落盘
    // 值即回退值，与 Web 数据口径一致；审计 B-1）。
    let trimmed = ui.titleDraft.trimmingCharacters(
        in: .whitespacesAndNewlines)
    let final = trimmed.isEmpty ? "无标题" : trimmed
    if final != editor.title {
        editor.pushHistory()
        editor.title = final
        editor.scheduleSave()
        ui.backlinks = editor.library.backlinks(
            forTitle: editor.title,
            excludeId: editor.item.id)
    }
    if ui.titleDraft != final {
        ui.titleDraft = final
    }
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
            TextField("无标题", text: Binding(
                get: { ui.titleDraft },
                set: { ui.titleDraft = $0 }))
                .font(.system(size: 14, weight: .semibold))
                .tracking(-0.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(T.textMain)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit {
                    // Enter 提交并辞焦（审计 B-3）。
                    commitTitle()
                    titleFocused = false
                }
                .onChange(of: titleFocused) { f in
                    if f {
                        // 聚焦快照：Esc 还原以会话起点
                        // 为准（审计 B-3）。
                        ui.titleBase = editor.title
                        DiagLog.shared.log(.info,
                            "EDIT title session begin "
                            + "len=\(ui.titleDraft.unicodeScalars.count)")
                    } else {
                        commitTitle()
                    }
                }
                .opacity(truncated ? 0 : 1)
                .accessibilityHidden(truncated)
            if truncated {
                Text(scalarPrefix(ui.titleDraft, 10) + "…")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        DiagLog.shared.log(.info,
                            "EDIT title focus via=capsule")
                        titleFocused = true
                    }
            }
        }
        // meta 行：紧凑态整行不渲染（Web .scrolled 下
        // display:none 的等价），不留占位、不外漏。
        if !compact {
            Text(metaLine)
                .font(.system(size: 10))
                .foregroundStyle(T.textSecondary)
                .lineLimit(1)
        }
    }
    .padding(.horizontal, 20)
    .frame(width: capsuleWidth, height: 66)
    .glassControl(radius: Radius.titleCapsule)
    .animation(.easeInOut(duration: 0.2),
               value: capsuleWidth)
}

private var capsuleWidth: CGFloat {
    let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    let shown = ui.titleDraft.isEmpty
        ? "无标题"
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
    let metaFont = UIFont.systemFont(ofSize: 10)
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
    let maxW = max(avail, 66)
    return min(max(max(titleW, metaW) + 40, 66), maxW)
}

/// meta（Web 口径）：相对更新时间 · 正文字数。
private var metaLine: String {
    "\(editor.item.ago) · 共 \(editor.wordCount) 字"
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 4) {
                Text("背景色")
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(T.textMain)
                Text("为当前笔记设置底色")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        T.textMain.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible()), count: 4),
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
                                    .font(.system(
                                        size: 20,
                                        weight: .semibold))
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
                                .font(.system(size: 20))
                            Text("移除背景")
                                .font(.system(
                                    size: 15,
                                    weight: .semibold))
                                .tracking(-0.1)
                        }
                        Text("（恢复默认背景）")
                            .font(.system(size: 11))
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
        .background(T.overlayBg)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28)
            .stroke(T.overlayBorder, lineWidth: 0.5))
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
                             title: "撤销",
                             sub: "快捷键→ Cmd+Z / 三指左滑",
                             dimmed: !editor.canUndo) {
                        editor.undo()
                        ui.showMenu = false
                    }
                    menuItem(icon: "arrow.uturn.forward",
                             title: "重做",
                             sub: "快捷键→ Cmd+Shift+Z / 三指右滑",
                             dimmed: !editor.canRedo) {
                        editor.redo()
                        ui.showMenu = false
                    }
                    // 附件行上距 4（Web layers.rs 内联
                    // margin-top:4px，J2-F06）。
                    menuItem(icon: "paperclip",
                             title: "添加附件",
                             sub: "图片、PDF 或文本文件",
                             chevron: true) {
                        ui.showMenu = false
                        ui.showAttachChoice = true
                    }
                    .padding(.top, 4)
                    menuItem(icon: "square.and.arrow.up",
                             title: "导出笔记",
                             sub: "Markdown · HTML · PDF",
                             chevron: true) {
                        ui.showExport = true
                    }
                    // 背景行上距 4 + 图标紫（Web
                    // layers.rs 内联 margin-top:4px、
                    // palette stroke --color-purple，
                    // J2-F07/F08）。
                    menuItem(icon: "paintpalette",
                             title: "更换背景色",
                             sub: "为当前笔记设置专属底色",
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
                .overlayCard(radius: 22)
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
        VStack(spacing: 0) {
            // 头（Web .export-head 口径）：min-height 46、
            // 返回钮 46×46 圆形玻璃钮、标题 15/650 居中
            // （右侧等宽占位补偿）、下边线 0.5。
            HStack(spacing: 0) {
                Button {
                    ui.showExport = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
                }
                Text("导出笔记")
                    .font(.system(size: 15, weight: .semibold))
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
                             detail: "保存为 .md 文件") {
                    shareExported(editor.exportFile(
                        format: "md"))
                }
                exportChoice(badge: "<>", label: "HTML",
                             detail: "保存为独立网页") {
                    shareExported(editor.exportFile(
                        format: "html"))
                }
                exportChoice(badge: "PDF", label: "PDF",
                             detail: "打印或存储为 PDF") {
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
            Text("PDF 将生成文件，可通过分享存储或打印。")
                .font(.system(size: 10))
                .lineSpacing(4.5)
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
        .frame(width: 246)
        .overlayCard(radius: 22)
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
                        ? 9 : 11, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(T.accent)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 14,
                                      weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(T.textSecondary)
                }
                Spacer()
                Text("›")
                    .font(.system(size: 19))
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
                    .font(.system(size: 20))
                    .foregroundStyle(danger ? T.danger
                                     : (iconColor ?? T.accent))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15,
                                      weight: .semibold))
                        .tracking(-0.1)
                        .foregroundStyle(danger ? T.danger
                                         : T.textMain)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(T.textSecondary)
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: 18))
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
            // 整页落焦占位账（单列）：上 padding 168 +
            // 下 40，内容高至少视口 − 208，热区弹性吸
            // 收余高至页底。0.9.48 起下距再加 ui.kbPad
            // （键盘落定遮挡量，内容对键盘安全区免疫
            // 后的等价补偿；无键盘时恒 0、账面不变）。
            .frame(minHeight: max(0, ui.viewH - 208),
                   alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 168)
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
                Text("反向链接")
                    .font(.system(size: 12,
                                  weight: .semibold))
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
                                    .font(.system(size: 14))
                                    .foregroundStyle(
                                        T.textSecondary)
                                Text(memo.title.isEmpty
                                     ? "无标题" : memo.title)
                                    .font(.system(size: 14))
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
        // 52)，两模式同值；分隔线 1px 居中，两侧各
        // (gap-1)/2。分隔线色走 --border-color 档。
        let gap = min(52, max(28, ui.viewW * 0.032))
        let half = (gap - 1) / 2
        if editor.twoPaneIndependent {
            // 整页落焦占位账（independent）：外层上
            // padding 168 + 下 8 → 栏滚动视口高 =
            // viewH − 176；栏内容再扣自身底 padding
            // 24 → 栏 VStack minHeight = viewH − 200，
            // 两栏热区各自吸收本栏余高。
            let colMinH = max(0, ui.viewH - 200)
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
                    .padding(.trailing, half)
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
                        .padding(.leading, half)
                        .padding(.bottom, 24 + ui.kbPad)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 168)
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
                // 168 + 下 24 → 内容高至少 viewH − 192。
                // 下距同单列加 ui.kbPad（0.9.48）。
                .frame(minHeight: max(0, ui.viewH - 192),
                       alignment: .top)
                .padding(.horizontal, 16)
                .padding(.top, 168)
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
                .font(.system(size: 17))
                .foregroundStyle(T.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("双栏独立滚动")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text("平板与 PC 可分别滚动两栏")
                    .font(.system(size: 11))
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

    var items: [[String: Any]] {
        (block.node["attrs"] as? [String: Any])?["items"]
            as? [[String: Any]] ?? []
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
                                    .font(.system(size: 18))
                                    .opacity(ix == 0
                                        ? 0.4 : 0.3)
                                Text(ix == 0
                                    ? (editor.cardEditBlockId
                                        == block.id
                                        ? "点击添加"
                                        : "长按编辑添加")
                                    : "多张图片")
                                    .font(.system(size: 11))
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
            ForEach(Array(items.enumerated()),
                    id: \.offset) { ix, it in
                    GeometryReader { geo in
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
                            editor.imageTarget = ImageTarget(
                                fileId: it["fileId"] as? String,
                                urlString: (it["url"] as? String)
                                    ?? (it["src"] as? String),
                                name: (it["name"] as? String)
                                    ?? "图片")
                        }
                    }
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
                prompt: Text("粘贴音乐链接到这里，回车解析...")
                    .foregroundColor(T.textSecondary))
                .font(.system(size: 14))
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
                           block: BlockState)
        -> NSAttributedString {
        Marks.withRhythm(
            Marks.attributed(runs: runs(segs), base: base),
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
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: img.size.width)
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
                        library: library)
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
                .font(.system(size: 13, design: .monospaced))
                .lineSpacing(7.8)
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
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
            .padding(.vertical, 10)
            .padding(.leading, 17)
            .padding(.trailing, 14)
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
                    // 18，基字 16 时为 1.2/4.4；任务勾选
                    // 支维持 8 不动。小字号容器下钳 0
                    // （标记框 18 为既有原生几何）。
                    let isTask = item["checked"] != nil
                    HStack(alignment: .top,
                           spacing: isTask ? 8
                               : max(0, (ordered ? 1.4 : 1.2)
                                     * baseSize - 18)) {
                        if let checked = item["checked"]
                            as? Bool {
                            Image(systemName: checked
                                ? "checkmark.square.fill"
                                : "square")
                                .font(.system(size: 15))
                                .foregroundStyle(checked
                                    ? T.checkChecked
                                    : T.textSecondary)
                        } else {
                            Text(ordered
                                 ? "\(start + idx)."
                                 : "•")
                                .font(.system(size: baseSize))
                                .foregroundStyle(T.textMain)
                                .frame(width: 18,
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
            // 读，本项一并改 14。
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
                                    block: block),
                                interactive:
                                    MdRender.hasInteractive(cell),
                                textColor: T.quoteTextUI,
                                onOpenURL: { url in
                                    openURL(url)
                                    return .handled
                                })
                                .frame(maxWidth: 288,
                                       alignment: tableAlign(
                                           aligns, ci))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
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
                                    .frame(maxWidth: 288,
                                           alignment:
                                               tableAlign(
                                                   aligns, ci))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
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
                                .font(.system(size: 13))
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
                                                .font(.system(
                                                    size: 13))
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
                        .font(.system(size: 18,
                                      weight: .semibold))
                        .foregroundStyle(
                            T.calloutAccent(style))
                    Text(title)
                        .font(.system(size: 15,
                                      weight: .bold))
                        .foregroundStyle(T.textMain)
                    if folding != nil {
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11,
                                          weight: .semibold))
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

    var body: some View {
        let ml = renderMathml(tex: tex, display: true)
        if ml.isEmpty {
            Text(tex)
                .font(.system(size: 14, design: .monospaced))
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
                    .font(.system(size: 16))
                    .foregroundStyle(T.textMain)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
            }
            ForEach(Array(editor.mdBlocks(for: block)
                .enumerated()), id: \.offset) { idx, raw in
                MdBlockView(raw: raw, block: block,
                            library: editor.library)
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
        Group {
            if block.fileId != nil {
                // 带 fileId 的音乐卡 = 音频附件，走文件行。
                fileRow
            } else if isMusic, status == "loading" {
                skeleton
            } else if isMusic, status == "error",
                      !cardURL.isEmpty {
                errorCard
            } else if isMusic, status == "input" {
                // input 胶囊（Web 状态机同位：标题判
                // 定之前；批 K F7——此前无此分支，
                // input 态音乐块整块隐形）。
                inputPill
            } else if !title.isEmpty {
                readyCard
            } else if !isMusic {
                errCard
            } else if !cardURL.isEmpty {
                urlPill
            } else {
                // 空态胶囊（Web 状态机末支；批 K
                // F7——此前落 EmptyView 整块隐形）。
                // 此支只达音乐卡（链接卡已被 errCard
                // 截走、有 URL 已被 urlPill 截走）。
                emptyPill
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineSpacing(14 * 0.4)
                    .lineLimit(2)
                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                        .lineSpacing(12 * 0.3)
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
            return s.isEmpty ? "音乐" : s
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
                .font(.system(size: 12))
            Circle()
                .fill(T.textSecondary.opacity(0.4))
                .frame(width: 3, height: 3)
            Text(sourceText)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(T.textSecondary)
    }

    // ── link-card 无标题 err 卡（Web 口径） ────────
    private var errCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(host.isEmpty ? cardURL : host)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
                .lineLimit(2)
            HStack(spacing: 5) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                Circle()
                    .fill(T.textSecondary.opacity(0.4))
                    .frame(width: 3, height: 3)
                Text(cardURL)
                    .font(.system(size: 11))
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
                .font(.system(size: 20))
                .foregroundStyle(T.textMain)
            // URL 本身可点开（Web error 卡锚口径，
            // 批 K F8）：openCard 内含 http(s) 前缀
            // 闸，与 Web safe_http_url 白名单降级
            // 等价（不过闸则点按无动作）；卡面其余
            // 部分不挂手势（Web cursor default）。
            Text(cardURL)
                .font(.system(size: 14))
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
                    .font(.system(size: 13, weight: .semibold))
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
            .font(.system(size: 14))
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
                .font(.system(size: 17))
                .foregroundStyle(T.textMain)
            Text(Lang.t("media.music_click_hint"))
                .font(.system(size: 14))
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
                .font(.system(size: 17))
                .foregroundStyle(T.textMain)
            Text(cardURL)
                .font(.system(size: 14))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            if status == "error" {
                Text(Lang.t("media.preview_unavailable"))
                    .font(.system(size: 11))
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

    private var fileRow: some View {
        let name = library.attachmentName(for: block.fileId)
            ?? (block.node["name"] as? String)
            ?? (block.node["title"] as? String)
            ?? "音频"
        return AttachmentRow(icon: "music.note", name: name,
                             hint: "音乐",
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
/// 态），16:9 占位、圆角 22。
struct VideoBlockView: View {
    @ObservedObject var block: BlockState
    var library: Library
    @StateObject private var holder = VideoHolder()

    var body: some View {
        Group {
            if let player = holder.player {
                InlinePlayerView(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.cardS))
            } else {
                RoundedRectangle(cornerRadius: Radius.cardS)
                    .fill(T.borderSoft)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(T.textSecondary)
                    }
            }
        }
        .onAppear { prepare() }
    }

    private func prepare() {
        guard holder.player == nil else { return }
        if let s = (block.node["url"] as? String)
            ?? block.imageURL,
           let u = URL(string: s) {
            holder.player = AVPlayer(url: u)
            return
        }
        if let fid = block.fileId {
            let lib = library
            DispatchQueue.global(qos: .userInitiated).async {
                let data = lib.attachmentData(fid)
                let path = NSTemporaryDirectory()
                    + "video-\(fid).mov"
                try? data.write(
                    to: URL(fileURLWithPath: path))
                DispatchQueue.main.async {
                    holder.player = AVPlayer(
                        url: URL(fileURLWithPath: path))
                }
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
    /// 宽屏（spread）度量切换（Web 口径）：padding
    /// 14/12、gap 8；常态 20/16、gap 10。半径恒 cardL
    /// ——Web .attachment-file 无宽屏变值（S1 裁断
    /// 2026-11-27：旧宽屏 22 缺 Web 实据，统一 32）。
    var wide: Bool = false

    var body: some View {
        HStack(spacing: wide ? 8 : 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(T.textMain)
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(T.textMain)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(T.fillHoverStrong, in: Capsule())
        }
        .padding(.horizontal, wide ? 14 : 20)
        .padding(.vertical, wide ? 12 : 16)
        .contentCard(radius: Radius.cardL)
    }
}

struct AttachmentBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var shareState = ShareState()

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
            if isImageAttachment, let first = files.first {
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
                        editor.imageTarget = ImageTarget(
                            fileId: first.0, urlString: nil,
                            name: first.1)
                    }
            } else {
                ForEach(files, id: \.0) { fid, name in
                    AttachmentRow(
                        icon: "paperclip",
                        name: name, hint: "打开",
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
                                editor.imageTarget =
                                    ImageTarget(
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
                    Text("附件（无文件）")
                        .font(.system(size: 14))
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

    /// Web 口径：node.image == true 的单文件附件整幅
    /// 呈现（多文件形态仍走文件行）。
    private var isImageAttachment: Bool {
        (block.node["image"] as? Bool) == true
            && files.count == 1
    }
}

struct ImgTextBlockView: View {
    @ObservedObject var block: BlockState
    @ObservedObject var editor: EditorModel
    @StateObject private var ui = ImgTextUI()
    @StateObject private var loader = ImageLoader()

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
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
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
                        Text("点击添加图片")
                            .font(.system(size: 13))
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
                                // 裁外角），占半幅整高。
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
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
                                    .font(.system(size: 24))
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
                        library: editor.library)
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
                    .navigationTitle("图文文本")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { ui.editing = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
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
        editor.imageTarget = ImageTarget(
            fileId: block.fileId, urlString: block.imageURL,
            name: (block.node["name"] as? String) ?? "图片")
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
        Text(block.text.isEmpty ? "点击查看完整文本" : block.text)
            .font(.system(size: 14))
            .lineSpacing(14 * 0.7)
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
    static var textMain: Color { dyn(0x1A1A1A, 0xFFFFFF) }
    static var textSecondary: Color { dyn(0x68686D, 0x98989D) }
    /// 玻璃控件标签色（Web --glass-label-color
    /// #48494F/#D1D1D6）：展开钮等玻璃药丸文字专用，
    /// 与 textSecondary 色值不同、不可代用（C-A6 前
    /// 提；线 4 C2 同面令牌缺口，设置族随批 E 收编）。
    static var glassLabel: Color { dyn(0x48494F, 0xD1D1D6) }
    static var accent: Color { dyn(0x007AFF, 0x007AFF) }
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
    /// 待办未选圈边（Web --md-checkbox-border #73737A）。
    static var checkBorder: Color { dyn(0x73737A, 0x73737A) }
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
    /// 压暗；无色回根背景。
    static func memoBg(_ hex: String?) -> Color {
        guard let hex, let rgb = rgbOf(hex) else { return bg }
        return Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(
                    red: rgb.0 * 0.55, green: rgb.1 * 0.55,
                    blue: rgb.2 * 0.55, alpha: 1)
            }
            return UIColor(red: rgb.0, green: rgb.1,
                           blue: rgb.2, alpha: 1)
        })
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

    private func cover(names: [String: String],
                       types: [String: String])
        -> (String?, String?) {
        func probe(_ nodes: [[String: Any]])
            -> (String?, String?)? {
            for n in nodes {
                let ty = n["type"] as? String ?? ""
                let attrs = n["attrs"] as? [String: Any] ?? [:]
                switch ty {
                case "image", "imgTextCard", "imageTextRow":
                    if let f = attrs["fileId"] as? String,
                       !f.isEmpty { return (f, nil) }
                    if let u = (attrs["url"] as? String)
                        ?? (attrs["src"] as? String) {
                        return (nil, u)
                    }
                case "gallery":
                    let items = attrs["items"]
                        as? [[String: Any]] ?? []
                    for it in items {
                        if let f = it["fileId"] as? String,
                           !f.isEmpty { return (f, nil) }
                        if let u = it["url"] as? String {
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
                DinoView(size: size * 0.72)
                    .frame(width: size, height: size)
                    .glassControl(radius: 999)
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

    func refreshIfNeeded() {
        if let (w, ts) = readCache(),
           Date().timeIntervalSince1970 - ts < 1800 {
            now = w
            return
        }
        guard !inFlight else { return }
        inFlight = true
        Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 1_500_000_000)
            await self.fetch()
            self.inFlight = false
        }
    }

    private func fetch() async {
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
            ipCity: ipCity) {
            await MainActor.run {
                self.now = w
            }
            return
        }
        if let w = await fetchCaiyun(
            lat: lat, lng: lng, ipCity: ipCity) {
            await MainActor.run {
                self.now = w
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
                               key: String, ipCity: String)
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
        writeCache(w)
        DiagLog.shared.log(.info,
            "WEATHER fetched provider=qweather "
            + "\(temp)° \(city) \(text)")
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
                             ipCity: String) async -> Now? {
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
        writeCache(w)
        DiagLog.shared.log(.info,
            "WEATHER fetched provider=caiyun-fallback "
            + "\(temp)° \(ipCity) \(w.text)")
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
struct ListView: View {
    @ObservedObject var library: Library
    @EnvironmentObject private var langStore: LangStore
    @ObservedObject private var weather =
        WeatherService.shared
    @StateObject private var nav = NavState()
    @StateObject private var groupsCache = GroupsCache()

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

    final class NavState: ObservableObject {
        @Published var dest: Dest?
        /// 编辑器转场宿主（0.9.50 呈现重构）：新建/打
        /// 开/关联打开三路呈现都经它以 UIKit push 承
        /// 载（见 MomentEditorTransition.swift）；导航
        /// 控制器由 EditorNavProbe 在根视图入窗后登记。
        let editorHost = EditorTransitionHost()
        @Published var query = ""
        @Published var searchOpen = false
        @Published var expandedKeys: Set<String> = []
        @Published var scrollOffset: CGFloat = 0
        var firstRowMinY: CGFloat?
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
                        groupHeader(group.title)
                        sublist(group: group, kind: "img",
                                memos: group.images)
                        if !group.images.isEmpty
                            && !group.texts.isEmpty {
                            // 图/文子列间隔（C-A3）：合
                            // 成 = 上卡 inset 3 + 本行 34
                            // + 下卡 inset 3 = 40（Web
                            // margin 24 + gap 16）。
                            Color.clear
                                .frame(height: 34)
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
                    if visibleMemos.isEmpty {
                        emptyRow
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: "momentList")
                }
                header
                if library.pendingDeletion != nil {
                    undoToast
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .bottom)
                }
            }
            .animation(.spring(response: 0.28,
                               dampingFraction: 0.86),
                       value: library.pendingDeletion?.id ?? "")
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
            // 形态切换后探针基线重捕（两形态内容坐标
            // 原点不同，沿用旧基线会跳一帧进度）。
            nav.firstRowMinY = nil
            nav.scrollOffset = 0
        }
        let cols = s.width >= 1280 ? 4 : 3
        if cols != nav.homeCols { nav.homeCols = cols }
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

    /// 列表首行占位（悬浮页眉的高度补偿 82+6）+ 滚动
    /// 探针本体：行本体随内容连续移动，onGeometryChange
    /// 直读命名空间 minY（基线捕获制，同编辑页）。
    private var spacerRow: some View {
        Color.clear
            .frame(height: 88)
            .onGeometryChange(for: CGFloat.self) { geo in
                geo.frame(in: .named("momentList")).minY
            } action: { y in
                probeAction(y)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private var noticeRow: some View {
        Text(library.notice)
            .font(.system(size: 12))
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
                .font(.system(size: 11))
                .foregroundStyle(T.warning)
            Text(Lang.t("rescue.readonly_banner"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(T.textMain)
            Spacer(minLength: 0)
            Button(Lang.t("rescue.enter")) {
                library.exitReadOnlyToRescue()
            }
            .font(.system(size: 12, weight: .semibold))
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
    /// 紧凑进度：scrollY/30（Web 口径）。
    private var compactP: CGFloat {
        min(max(nav.scrollOffset / 30, 0), 1)
    }

    // 页眉（Web 口径）：左侧 72 头像即标题区（点进设置，
    // 无大文本标题）+ 右侧 66 高两态搜索胶囊；滚动紧凑
    // 时头像渐缩淡出、搜索隐藏、中央出现「此刻」胶囊。
    private var header: some View {
        ZStack {
            HStack(alignment: .top, spacing: 12) {
                Button {
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
                .allowsHitTesting(compactP < 0.5)
                Spacer()
                searchCapsule
                    .opacity(1 - compactP)
                    .allowsHitTesting(compactP < 0.5)
                    // 搜索展开/收起交叉淡入（M5）。
                    .animation(.easeInOut(duration: 0.2),
                               value: nav.searchOpen)
            }
            // 「此刻」小标题（Web 真值）：进度满才出现
            // （Web 为 visibility 阈值切换），呈现加
            // 180ms 淡入（系统惯例）；此前全程半透明
            // 淡入，玻璃胶囊半透态最显「脏」，是硬切
            // 感知的落点。
            Button {
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

    @ViewBuilder
    private var searchCapsule: some View {
        if nav.searchOpen {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(T.textSecondary)
                TextField(Lang.t("search.placeholder"),
                          text: Binding(
                    get: { nav.query },
                    set: { nav.query = $0
                           library.search($0) }))
                    .font(.system(size: 15))
                    .frame(width: 140, height: 40)
                if !nav.query.isEmpty {
                    Button {
                        nav.query = ""
                        library.search("")
                        nav.searchOpen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(T.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .glassCard(radius: 999)
            .transition(.opacity)
        } else {
            Button {
                nav.searchOpen = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                    Text(Lang.t("search.trigger"))
                        .font(.system(size: 14))
                        .tracking(-0.1)
                        .foregroundStyle(T.glassLabel)
                }
                .foregroundStyle(T.textSecondary)
                .padding(.horizontal, 18)
                .frame(height: 66)
                .glassControl(radius: 999)
            }
            .buttonStyle(CardPressStyle())
            .transition(.opacity)
        }
    }

    /// 组内子列（先图后文）：>2 折叠——首卡 meta 带
    /// 「▼ 展开 N 条」、展开后末卡带「▲ 收起」（Web 口径）。
    @ViewBuilder
    private func sublist(group: MemoGroup, kind: String,
                         memos: [MemoItem]) -> some View {
        let key = "\(group.id)-\(kind)"
        let expanded = nav.expandedKeys.contains(key)
        let folded = memos.count > 2 && !expanded
        let shown = folded ? Array(memos.prefix(1)) : memos
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
                .font(.system(size: 19))
                .foregroundStyle(T.textMain)
            Text(Lang.t("list.deleted_toast"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(T.textMain)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
            Button(Lang.t("action.undo")) {
                library.undoDeletion()
            }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .buttonStyle(CardPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlayCard(radius: 28)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        // 进场（Web 口径）：220ms 弹簧上滑 + 淡入。
        .transition(.move(edge: .bottom)
            .combined(with: .opacity))
    }

    // ── 首页宽屏网格（Web 口径）──────────────────
    /// 网格形态：ScrollView + LazyVGrid（3/4 列、gap
    /// 14、容器上限 1240 居中、左右 24）；组标题整行
    /// 横跨；方卡 aspect 1/1、radius 26；折叠组首卡
    /// 叠卡呈现。左滑不可用，长按菜单补删除/置顶。
    private var gridHome: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 88)
                    .onGeometryChange(for: CGFloat.self) {
                        geo in
                        geo.frame(in: .named("momentList"))
                            .minY
                    } action: { y in
                        probeAction(y)
                    }
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    if library.isReadOnly {
                        readonlyBannerContent
                            .gridCellColumns(nav.homeCols)
                    }
                    if !library.notice.isEmpty {
                        Text(library.notice)
                            .font(.system(size: 12))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                            .gridCellColumns(nav.homeCols)
                    }
                    if !library.loadFailed && !library.isReadOnly {
                        newCardSquare
                    }
                    ForEach(groups) { group in
                        Text(group.title)
                            .font(.system(size: 13,
                                          weight: .semibold))
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)
                            .padding(.top, 8)
                            .gridCellColumns(nav.homeCols)
                        gridSublist(group: group, kind: "img",
                                    memos: group.images)
                        gridSublist(group: group, kind: "txt",
                                    memos: group.texts)
                    }
                    if visibleMemos.isEmpty {
                        gridEmpty
                    }
                }
                .frame(maxWidth: 1240)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
        .coordinateSpace(name: "momentList")
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14),
              count: nav.homeCols)
    }

    private func probeAction(_ y: CGFloat) {
        if nav.firstRowMinY == nil {
            nav.firstRowMinY = y
        }
        let base = nav.firstRowMinY ?? y
        nav.scrollOffset = max(0, base - y)
    }

    @ViewBuilder
    private func gridSublist(group: MemoGroup, kind: String,
                             memos: [MemoItem]) -> some View {
        let key = "\(group.id)-\(kind)"
        let expanded = nav.expandedKeys.contains(key)
        let folded = memos.count > 2 && !expanded
        let shown = folded ? Array(memos.prefix(1)) : memos
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
                .font(.system(size: 44))
                .foregroundStyle(
                    T.textSecondary.opacity(0.55))
            Text(state.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.textMain)
            Text(state.desc)
                .font(.system(size: 13))
                .lineSpacing(7)
                .foregroundStyle(T.textSecondary)
                .frame(maxWidth: 280)
                .multilineTextAlignment(.center)
            Button {
                state.run()
            } label: {
                Text(state.action)
                    .font(.system(size: 14,
                                  weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(T.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.vertical, 56)
        .gridCellColumns(nav.homeCols)
    }

    private var newCardSquare: some View {
        Button {
            createAndOpen()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(Lang.t("list.new_note"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(T.textSecondary)
                Text("\(Lang.t("list.now"))\u{00A0}\u{00A0}"
                     + "\(Lang.t("list.new_note_sub"))")
                    .font(.system(size: 12))
                    .foregroundStyle(T.glassLabel)
                Spacer(minLength: 0)
                if let w = weather.now {
                    // 天气底部整行（C-A5，Web 宽屏规则）：
                    // 温度左、城况右、同行两端分布；原
                    // 右下两行堆叠为自创形态。
                    HStack {
                        Text("\(w.temp)°")
                            .font(.system(size: 16,
                                          weight: .semibold))
                            .foregroundStyle(T.textMain)
                        Spacer()
                        Text([w.city, w.text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " "))
                            .font(.system(size: 12))
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
                    squareImageCard(memo, collapse: collapse)
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
                    library.togglePin(memo)
                } label: {
                    Label(memo.pinned
                          ? Lang.t("action.unpin")
                          : Lang.t("action.pin"),
                          systemImage: memo.pinned
                            ? "pin.slash" : "pin")
                }
                Button(role: .destructive) {
                    library.softRemove(memo)
                } label: {
                    Label(Lang.t("action.delete"),
                          systemImage: "trash")
                }
            }
        }
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
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 12))
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
        _ memo: MemoItem, collapse: (() -> Void)?
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(T.textMain)
                    .lineLimit(1)
                squareTags(memo, small: true)
                // meta 行：文案 + 收起药丸同行（小差
                // 9，此前收起钮是 meta 行外的独立行
                // 纯文字、纵位差一行）。
                HStack(spacing: 6) {
                    Text("\(memo.ago) · \(memo.summary(isImage: true))")
                        .font(.system(size: 12))
                        .foregroundStyle(T.glassLabel)
                        .lineLimit(1)
                    if let collapse {
                        Spacer(minLength: 8)
                        Button(Lang.t("list.collapse")) {
                            collapse()
                        }
                            .font(.system(size: 11))
                            .foregroundStyle(T.glassLabel)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassControl(radius: 14)
                            .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 78)
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
                Text("#\(tag)")
                    .font(.system(size: small ? 10 : 11))
                    .foregroundStyle(T.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, small ? 6 : 7)
                    .padding(.vertical, small ? 1 : 2.5)
                    .background(T.glassControlTint,
                                in: Capsule())
            }
            if memo.tags.count > 2 {
                Text("+\(memo.tags.count - 2)")
                    .font(.system(size: small ? 10 : 11))
                    .foregroundStyle(T.textSecondary)
                    .padding(.horizontal, small ? 6 : 7)
                    .padding(.vertical, small ? 1 : 2.5)
                    .background(T.glassControlTint,
                                in: Capsule())
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
                .font(.system(size: 11))
                .foregroundStyle(T.glassLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassControl(radius: 14)
                .buttonStyle(.plain)
        } else if let collapse {
            Button(Lang.t("list.collapse")) { collapse() }
                .font(.system(size: 11))
                .foregroundStyle(T.glassLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassControl(radius: 14)
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
                        .font(.system(size: 16,
                                      weight: .semibold))
                        .foregroundStyle(T.textSecondary)
                    Text("\(Lang.t("list.now"))\u{00A0}\u{00A0}"
                         + "\(Lang.t("list.new_note_sub"))")
                        .font(.system(size: 12))
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
                            .font(.system(size: 16,
                                          weight: .semibold))
                            .tracking(-0.5)
                            .foregroundStyle(T.textMain)
                        Text([w.city, w.text]
                            .filter { !$0.isEmpty }
                            .joined(separator: " "))
                            .font(.system(size: 12))
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

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: groupFontSize,
                          weight: .semibold))
            .foregroundStyle(T.textSecondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 24, leading: 20,
                                      bottom: 6, trailing: 16))
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
                library.softRemove(memo)
            } label: {
                Label(Lang.t("action.delete"),
                      systemImage: "trash")
            }
            .tint(T.danger)
            Button {
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
                            Text("#\(tag)")
                                .font(.system(size: 10))
                                .foregroundStyle(
                                    T.textSecondary)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    T.glassControlTint,
                                    in: Capsule())
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
                    .font(.system(size: 11))
                    .foregroundStyle(T.glassLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassControl(radius: 14)
                    .buttonStyle(.plain)
            }
            if let collapse = collapseHint {
                Button(Lang.t("list.collapse")) { collapse() }
                    .font(.system(size: 11))
                    .foregroundStyle(T.glassLabel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassControl(radius: 14)
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
                .font(.system(size: 44))
                .foregroundStyle(T.textSecondary.opacity(0.55))
            Text(state.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(T.textMain)
            Text(state.desc)
                .font(.system(size: 13))
                .foregroundStyle(T.textSecondary)
            Button(state.action) { state.run() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(T.accent, in: Capsule())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// ── 子页骨架（Web 口径：左上玻璃返回圆钮 + 居中紧凑标题
// 胶囊 + 内容 126 顶距） ─────────────────────────────
struct CompactTitle: View {
    var text: String
    var body: some View {
        Text(text)
            // 单行不折（Web .page-title.compact 的
            // nowrap 口径）：长名横向溢出由外层居中承
            // 载。此前漏设，长文件名在胶囊内折成多行
            // ——用户实报的图片页标题异形（排查 #2 只
            // 对了「无截断」一半、漏了 nowrap 一半）。
            .lineLimit(1)
            .font(.system(size: 17, weight: .semibold))
            .tracking(-0.3)
            .foregroundStyle(T.textMain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .glassCard(radius: 20)
    }
}

struct ChromeView<Content: View>: View {
    var title: String
    var onBack: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            content()
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(T.textMain)
                        .frame(width: 46, height: 46)
                        .glassControl(radius: 999)
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
    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
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
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(T.accent)
                        .frame(width: 24, height: 24)
                }
                // 标题→meta 盒距 6（M1）：Web
                // .item-left gap 4 + .set-row
                // .item-meta margin-top 2 合成。
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
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
                        .font(.system(size: 12))
                    }
                }
                Spacer()
                if chevron {
                    Text("›")
                        .font(.system(size: 18))
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(T.accent)
                    .frame(width: 28, height: 28,
                           alignment: .leading)
                // 标题→描述 6（.backup-row-title
                // margin-bottom 6）。
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(
                            size: 16, weight: .semibold))
                        .foregroundStyle(T.textMain)
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundStyle(T.glassLabel)
                }
                Spacer()
                Text("›")
                    .font(.system(size: 18))
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

    final class SettingsNav: ObservableObject {
        @Published var route: Sub?
    }

    /// MCP 桥协调器（M1）：桥行 meta 随链路状态走。
    @ObservedObject private var bridge =
        BridgeCoordinator.shared

    enum Sub: Identifiable {
        case backup, gestures, language, diag, bridge, weather
        var id: String {
            switch self {
            case .backup: return "backup"
            case .gestures: return "gestures"
            case .language: return "language"
            case .diag: return "diag"
            case .bridge: return "bridge"
            case .weather: return "weather"
            }
        }
    }

    /// 主页天气行状态词：与 WeatherView 共用
    /// WeatherService.keySource 派生（单一真源）。
    private func weatherSourceWord(
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

    private var weatherMeta: String {
        Lang.tf("settings.weather_status", [
            "qw": weatherSourceWord(
                WeatherService.keySource("qweather")),
            "cy": weatherSourceWord(
                WeatherService.keySource("caiyun")),
        ])
    }

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
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t(
                                "settings.font_system_note"))
                                .font(.system(size: 12))
                                .foregroundStyle(T.textSecondary)
                        }
                        Spacer()
                        Text(Lang.t("settings.follow_system"))
                            .font(.system(size: 13))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: 32)

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
                    }
                    .glassCard(radius: 28)

                    // 天气组（分组方案 A）：整组下移至
                    // 数据组之后、关于组之前，恢复 Web
                    // 「外观 → 数据 → 关于」主序。主页
                    // 只留状态入口，表单移入 WeatherView
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
                           meta: weatherMeta) {
                        nav.route = .weather
                    }
                    .glassCard(radius: 28)

                    // 组距账（S1 重推）：天气卡改与
                    // 数据组同型导航行卡（.backup-card
                    // 口径 margin-bottom 16）+ page-gap
                    // 12 + 组头内联 4 = 32。
                    SectionHeader(text: Lang.t("settings.about"),
                                  topPad: 32)
                    VStack(spacing: 0) {
                        HStack {
                            Text(Lang.t("settings.version"))
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("0.9.53")
                                .font(.system(size: 14))
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        rowDivider
                        HStack {
                            Text(Lang.t("settings.contact"))
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Spacer()
                            Text("overcanopies@gmail.com")
                                // 值字号（M7）：Web 关于
                                // 行内联 0.85rem ≈ 13.6。
                                .font(.system(size: 13.6))
                                .foregroundStyle(T.textSecondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .glassCard(radius: 28)

                    Text(Lang.t("settings.footer"))
                        .font(.system(size: 12).italic())
                        .foregroundStyle(
                            T.textSecondary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 126)
                .padding(.bottom, 40)
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
            case nil:
                EmptyView()
            }
        }
        .onAppear {
            // 页进入行（G5，Web SET settings enter 口
            // 径；转场后缀原生系统转场改判不带）。
            DiagLog.shared.log(.info, "SET settings enter")
        }
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

    final class BackupUI: ObservableObject {
        @Published var confirmExport = false
        @Published var showImporter = false
        @Published var confirmImport = false
        @Published var stagedStats: (Int, Int)?
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
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(T.textMain)
                            // 描述（M2）：分隔点在 Web 为
                            // 独立 span opacity 0.3，分段
                            // 拼接承接（各段自带色，外层
                            // 只给字号避免覆盖段色）。
                            heroDesc
                                .font(.system(size: 13))
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(18)
                        .glassCard(radius: 30)

                        // 超期横幅（C3）：独立横幅卡——
                        // radius 30、0.5px warning 边、
                        // 内距横 18 纵 12、13px/1.5
                        // warning 色，hero 后下距 18。
                        if stale {
                            Text(Lang.t("backup.stale_banner"))
                                .font(.system(size: 13))
                                .lineSpacing(6.5)
                                .foregroundStyle(T.warning)
                                .frame(maxWidth: .infinity,
                                       alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(
                                    T.contentBg,
                                    in: RoundedRectangle(
                                        cornerRadius: 30))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: 30)
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
                        .glassCard(radius: 28)
                        .padding(.top, 18)

                        Text(Lang.t("backup.icloud_note"))
                            .font(.system(size: 13))
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
                            .glassCard(radius: 28)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 126)
                    .padding(.bottom, 40)
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
                        .font(.system(size: 19))
                        .foregroundStyle(toast.isError
                            ? T.danger : T.success)
                    Text(toast.text)
                        .font(.system(size: 14,
                                      weight: .medium))
                        .lineSpacing(5)
                        .foregroundStyle(T.textMain)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .overlayCard(radius: 28)
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
                if let stats = library.stageImport(from: url) {
                    ui.stagedStats = stats
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
                ShareSheet(url: url)
            }
        }
        .onAppear {
            // 页进入行（G5，Web BACKUP backup enter）。
            DiagLog.shared.log(.info, "BACKUP backup enter")
        }
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
                        .font(.system(size: 18,
                                      weight: .bold))
                        .foregroundStyle(T.textMain)
                    Text(isExport
                        ? Lang.t("backup.export_msg")
                        : Lang.t("backup.import_msg"))
                        .font(.system(size: 13))
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
                                    ui.shareURL = url
                                    showToast(
                                        Lang.t("status.shared"),
                                        isError: false)
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
                            } else if let stats = library
                                .commitStagedImport() {
                                showToast(
                                    Lang.tf("status.imported",
                                            ["n": "\(stats.0)",
                                             "m": "\(stats.1)"]),
                                    isError: false)
                            } else {
                                showToast(
                                    Lang.t("status.import_error"),
                                    isError: true)
                            }
                        } label: {
                            Text(isExport
                                ? Lang.t("backup.confirm_export")
                                : Lang.t("backup.confirm_import"))
                                // 按钮字（M3）：Web
                                // .backup-btn 14/650 →
                                // 14/600 定案口径。
                                .font(.system(
                                    size: 14,
                                    weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    T.accent.opacity(0.86),
                                    in: RoundedRectangle(
                                        cornerRadius: 999))
                        }
                        .buttonStyle(.plain)
                        Button {
                            ui.confirmExport = false
                            ui.confirmImport = false
                        } label: {
                            Text(Lang.t("action.cancel"))
                                .font(.system(
                                    size: 14,
                                    weight: .semibold))
                                .foregroundStyle(T.textMain)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    T.contentBg,
                                    in: RoundedRectangle(
                                        cornerRadius: 999))
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
                .glassCard(radius: 28)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(opSub(op))
                    .font(.system(size: 12))
                    .foregroundStyle(T.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            // 类型徽章（C10）：9px/700/大写、内距
            // 1/6、radius 999、玻璃边。
            Text(op.kind == "export"
                ? Lang.t("backup.kind_export")
                : Lang.t("backup.kind_restore"))
                .font(.system(size: 9, weight: .bold))
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
                                .font(.system(size: 25))
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
                                        size: 14, weight: .semibold))
                                    .lineSpacing(5.6)
                                    .foregroundStyle(T.textMain)
                                Text(row.2)
                                    .font(.system(size: 12))
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
                .glassCard(radius: 28)
                .padding(.horizontal, 20)
                .padding(.top, 126)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // 页进入行（G5，Web SET gestures enter）。
            DiagLog.shared.log(.info, "SET gestures enter")
        }
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
            UserDefaults.standard.removeObject(
                forKey: "weatherCacheV1")
            flashSaved(name)
            logSaved()
        }

        func clear(_ name: String) {
            guard !WeatherService.customKey(name).isEmpty
            else { return }
            UserDefaults.standard.removeObject(
                forKey: "weatherKey_" + name)
            setValue("", for: name)
            UserDefaults.standard.removeObject(
                forKey: "weatherCacheV1")
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
                        .font(.system(size: 12))
                        .foregroundStyle(T.textSecondary)
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .padding(16)
                        .glassCard(radius: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 126)
                .padding(.bottom, 40)
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
                    .font(.system(size: 16,
                                  weight: .semibold))
                    .foregroundStyle(T.textMain)
                Spacer()
                Text(showSaved
                     ? Lang.t("settings.weather_saved")
                     : sourceWord(source))
                    .font(.system(
                        size: 12,
                        weight: (showSaved || source == .custom)
                            ? .bold : .regular))
                    .foregroundStyle(
                        (showSaved || source == .custom)
                            ? T.accent : T.textSecondary)
            }
            Text(effectiveText(source))
                .font(.system(size: 12))
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
                .font(.system(size: 14))
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
                        .font(.system(size: 15))
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
                    .font(.system(size: 12))
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
            .font(.system(size: 13))
            .foregroundStyle(T.accent)
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassCard(radius: 32)
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
                .padding(.horizontal, 20)
                .padding(.top, 126)
                .padding(.bottom, 40)
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
                    .font(.system(size: 16,
                                  weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(T.textSecondary)
            }
            Spacer()
            if !status.isEmpty {
                Text(status)
                    .font(.system(
                        size: 12,
                        weight: active ? .bold : .regular))
                    .foregroundStyle(active
                        ? T.accent : T.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .glassCard(radius: 32)
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
    @StateObject private var loader = ImageLoader()
    @StateObject private var flags = ImgPageFlags()

    /// 打点去重标志（@State 宏在本工具链不可用，走
    /// ObservableObject 持有）。
    private final class ImgPageFlags: ObservableObject {
        @Published var loggedOpen = false
        @Published var loggedClose = false
    }

    /// 标题（Web 口径）：fileId 在时以附件清单真实名
    /// 为唯一真值（调用点名只作兜底）；URL 图无清单
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
                // 可用区 = 全屏减悬浮页头让位 66（图判定
                // 与呈现同用此高，边界图不走错分支）。
                let availH = geo.size.height - 66
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
                        Text("图片加载失败")
                            .foregroundStyle(T.textSecondary)
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity,
                                   maxHeight: .infinity)
                    }
                }
                .padding(.top, 66)
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
    }
}

/// 开屏时序状态（口径 = 原生壳工程 NativeSplash
/// Timeline，用户 2026-11-26 提供的启动动画源码）：
/// 静止 500ms → progress 线性 1.0s 走完呼吸曲线 →
/// 再 1.0s 置 timelineComplete；退出条件 = 数据就
/// 绪（didLoad）&& timelineComplete，easeOut
/// 260ms 交叉淡出；减弱动态效果时 timelineComplete
/// 立即置位、淡出时长 0。资源缺失（构建异常）时宿
/// 主直接不呈现，绝不让开屏挡住应用。
final class SplashState: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var timelineComplete = false
    @Published var gone = false
}

struct SplashHostView: View {
    @ObservedObject var library: Library
    @StateObject private var state = SplashState()
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static var resourcesReady: Bool {
        Bundle.main.url(forResource: "MomentSplash-light-vector",
                        withExtension: "json") != nil
            && Bundle.main.url(
                forResource: "MomentSplash-dark-vector",
                withExtension: "json") != nil
    }

    /// 开屏底色（原壳 launchBackgroundColor 同值，与
    /// NativeMomentSplash 自身背景同源）：浅蓝
    /// (35,121,220) / 深 (31,31,33)。
    private var splashColor: Color {
        colorScheme == .dark
            ? Color(red: 31.0 / 255, green: 31.0 / 255,
                    blue: 33.0 / 255)
            : Color(red: 35.0 / 255, green: 121.0 / 255,
                    blue: 220.0 / 255)
    }

    var body: some View {
        // 宿主形态按原壳原样（2026-11-26 用户实报上下
        // 半透明条后核证）：底色垫层满屏 ignoresSafeArea
        // + 画布 ignoresSafeArea(.container) 全屏。此前
        // 两样都缺，画布被收进安全区、上下露出首页成
        // 半透明条。
        ZStack {
            if !state.gone {
                splashColor
                    .ignoresSafeArea()
                    .transition(.opacity)
                NativeMomentSplash(progress: state.progress)
                    .ignoresSafeArea(.container, edges: .all)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            } else {
                // 淡出后卸载画布（原壳以布尔移除呈现，
                // 同口径），仅留零命中空层。
                Color.clear.allowsHitTesting(false)
            }
        }
        .task(id: reduceMotion) {
            await runTimeline()
        }
        .onChange(of: library.didLoad) { _ in
            beginExitIfReady()
        }
    }

    private func runTimeline() async {
        DiagLog.shared.log(.info, "SPLASH show")
        if reduceMotion {
            state.timelineComplete = true
            beginExitIfReady()
            return
        }
        do {
            try await Task.sleep(
                nanoseconds: 500_000_000)
        } catch { return }
        guard !Task.isCancelled else { return }
        withAnimation(.linear(duration: 1.0)) {
            state.progress = 1
        }
        do {
            try await Task.sleep(
                nanoseconds: 1_000_000_000)
        } catch { return }
        guard !Task.isCancelled else { return }
        state.timelineComplete = true
        beginExitIfReady()
    }

    private func beginExitIfReady() {
        guard library.didLoad, state.timelineComplete,
              !state.gone else { return }
        withAnimation(.easeOut(duration: reduceMotion
            ? 0 : 0.26)) {
            state.gone = true
        }
        DiagLog.shared.log(.info, "SPLASH dismiss")
    }
}

@main
struct MomentApp: App {
    // 语言 store 先于 Library 声明：其 init 的存量
    // 判据须赶在 Library.load 开库建 moment.db 之前
    // （判据本体见 LangStore.hasExistingState）。
    @StateObject private var langStore = LangStore.shared
    @StateObject private var library = Library()
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
                if !library.bootIsSafe
                    && SplashHostView.resourcesReady {
                    SplashHostView(library: library)
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
            fatalError("Missing or invalid native splash vector resource: \(theme)")
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
        start = CGPoint(x: resource.start[0], y: resource.start[1])
        end = CGPoint(x: resource.end[0], y: resource.end[1])
        stops = resource.stops.map { stop in
            Gradient.Stop(color: Color(hex: stop.color).opacity(stop.opacity), location: CGFloat(stop.offset))
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("此刻启动图标")
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
