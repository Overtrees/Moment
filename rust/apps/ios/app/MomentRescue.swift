// Moment 安全模式页（自救机制 R1，0.9.45）：
// RescueView——启动连续未完成（或热更新指令强制）
// 时的安全模式页（状态呈现 + 尝试正常启动/导出
// 诊断/检查热修复/导出 ZIP）。规格见
// docs/reports/plan_native_rescue.md S3/S6；本
// 文件自 MomentApp.swift 拆出（拒绝上帝文件，
// 独立成文件）。
import SwiftUI
import Foundation

// ── 安全模式页（S3，R1 骨架）────────────────────
// 构建路径红线：只依赖 DiagLog + FileManager 元数
// 据 + OpsDirectives 缓存 + Library 的已判定状态
// （bootMode/prevLaunch*），不打开资料库、不调任
// 何 FFI 写——库或加载链坏透时本页仍起得来。本
// 页零「重置/删库」类按钮（总红线）；文案明示不
// 要删 App（删 App = 删库）。
// R2 附着点已落地：只读打开资料库（动作 3，
// S4——FFI openReadonly + 副本回退 + 门面拒写 +
// 只读横幅，门面与横幅在 Library / ListView，
// 本页只挂动作）。
// R3 附着点已落地：清除可再生缓存（动作 5，
// S7）；看门狗浮条 WatchdogBar（S8，挂载在根
// ZStack）；状态快照环（S5，状态区呈最新 +
// 上次两条）。
struct RescueView: View {
    @ObservedObject var library: Library
    @StateObject private var diag = DiagLog.shared
    @StateObject private var ops = OpsDirectives.shared
    @StateObject private var ui = RescueUI()
    @EnvironmentObject private var langStore: LangStore

    final class RescueUI: ObservableObject {
        @Published var shareURL: URL?
        @Published var lastRescue: String = ""
        @Published var dbBytes: Int = 0
        @Published var opsBusy = false
        @Published var cacheConfirm = false
        /// 快照环最新/上次两条摘要（S5 状态区）。
        @Published var snapLatest: String = ""
        @Published var snapPrev: String = ""
    }

    private var safeSource: String {
        if case .safe(_, _, let source) = library.bootMode {
            return source
        }
        return ""
    }

    /// 当前生效指令摘要（数据行口径，不本地化）：
    /// 来源 + 步数 + forceSafe 标记。
    private var opsSummary: String {
        let src = ops.lastSource.isEmpty
            ? "cache" : ops.lastSource
        return "src=\(src) "
            + "steps=\(ops.current.disableSteps.count) "
            + "forceSafe="
            + (ops.current.forceSafeMode ? "1" : "0")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(Lang.t("rescue.title"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(T.textMain)
                    .padding(.top, 72)
                Text(Lang.t("rescue.boundary"))
                    .font(.system(size: 14))
                    .foregroundStyle(T.textSecondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(16)
                    .glassCard(radius: Radius.panelS)
                    .padding(.top, 16)

                // 状态区（只读数据组：哨兵 + 文件元
                // 数据 + 指令摘要，不开库）。
                VStack(alignment: .leading, spacing: 8) {
                    statusRow(
                        Lang.t("rescue.status_prev_step"),
                        library.prevLaunchStep.isEmpty
                            ? "-" : library.prevLaunchStep)
                    statusRow(
                        Lang.t("rescue.status_streak"),
                        "\(library.prevLaunchStreak)")
                    statusRow("mode",
                              "safe src=\(safeSource)")
                    statusRow("DB", "\(ui.dbBytes) B")
                    statusRow("Diag",
                              "today=\(diag.today.count) "
                              + "archives="
                              + "\(diag.archives.count)")
                    statusRow("OPS", opsSummary)
                    if !ui.snapLatest.isEmpty {
                        statusRow("snap", ui.snapLatest)
                    }
                    if !ui.snapPrev.isEmpty {
                        statusRow("snapPrev", ui.snapPrev)
                    }
                    if !ui.lastRescue.isEmpty {
                        statusRow("lastRescue",
                                  ui.lastRescue)
                    }
                }
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(16)
                .glassCard(radius: Radius.panelS)
                .padding(.top, 12)

                // 动作 1（主）：尝试正常启动。清本次
                // 哨兵标记由 load() 的 launchMark 接
                // 管（进入即标「开库」）；成功 streak
                // 清零（launchDone 口径），再崩下次仍
                // 回本页。
                Button(action: tryNormal) {
                    Text(Lang.t("rescue.try_normal"))
                        .font(.system(size: 16,
                                      weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(T.accent, in: Capsule())
                }
                .buttonStyle(CardPressStyle())
                .padding(.top, 24)
                if ops.current.forceSafeMode {
                    // S13 明示：指令 forceSafeMode 在
                    // 位时，正常启动会在下次判定时被
                    // 指令带回安全模式（数据行口径）。
                    Text("OPS forceSafeMode=1 · "
                         + "next launch returns to safe mode")
                        .font(.system(size: 12,
                                      design: .monospaced))
                        .foregroundStyle(T.warning)
                        .padding(.top, 8)
                }

                VStack(spacing: 0) {
                    SetRow(title: Lang.t(
                            "rescue.export_diag"),
                           icon: "doc.text.magnifyingglass",
                           chevron: false) {
                        exportDiag()
                    }
                    rowDivider
                    SetRow(title: Lang.t(
                            "rescue.check_ops"),
                           icon: "arrow.triangle.2.circlepath",
                           chevron: false) {
                        checkOps()
                    }
                    rowDivider
                    // 动作 3（S4，R2）：只读打开资料
                    // 库。成功后切只读浏览态（ListView
                    // + 只读横幅），失败留本页（原因
                    // 在 Diag 的 RESCUE readonly 行）。
                    SetRow(title: Lang.t(
                            "rescue.open_readonly"),
                           icon: "eye",
                           chevron: false) {
                        openReadonly()
                    }
                    rowDivider
                    // 动作 4（S3）：导出备份 ZIP。
                    // 库未打开时置灰 + 原因文案，不
                    // 得假成功（只读打开 R2 落地后可
                    // 用）。SetRow 无禁用态，以 meta
                    // 承载原因、动作内 guard 兜底。
                    SetRow(title: Lang.t(
                            "rescue.export_zip"),
                           meta: library.isDbOpen
                            ? nil
                            : Lang.t(
                                "rescue.export_zip_unavailable"),
                           icon: "archivebox",
                           chevron: false) {
                        exportZipAction()
                    }
                    rowDivider
                    // 动作 5（S7，R3）：清除可再生缓
                    // 存。次级动作、带确认；定位明示
                    // 在确认文案里（只清缓存、不动数
                    // 据，见 RescueCacheCleaner）。
                    SetRow(title: Lang.t(
                            "rescue.cache_clear"),
                           icon: "arrow.counterclockwise.circle",
                           chevron: false) {
                        ui.cacheConfirm = true
                    }
                }
                .glassCard(radius: Radius.panel)
                .padding(.top, 16)
                .alert(Lang.t("rescue.cache_clear"),
                       isPresented: $ui.cacheConfirm) {
                    Button(Lang.t("rescue.cache_clear"),
                           role: .destructive) {
                        clearCaches()
                    }
                    Button(Lang.t("action.cancel"),
                           role: .cancel) {}
                } message: {
                    Text(Lang.t(
                        "rescue.cache_clear_confirm"))
                }
                if ui.opsBusy {
                    Text("OPS fetching…")
                        .font(.system(size: 12,
                                      design: .monospaced))
                        .foregroundStyle(T.textSecondary)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(T.bg)
        .sheet(isPresented: Binding(
            get: { ui.shareURL != nil },
            set: { if !$0 { ui.shareURL = nil } })) {
            if let url = ui.shareURL {
                ShareSheet(url: url)
            }
        }
        .onAppear { refreshStatus() }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(T.borderSoft)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    private func statusRow(_ k: String, _ v: String)
        -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(T.textSecondary)
                .frame(width: 104, alignment: .leading)
            Text(v)
                .font(.system(size: 12,
                              design: .monospaced))
                .foregroundStyle(T.textMain)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func refreshStatus() {
        DiagLog.shared.loadIfNeeded()
        let s = LaunchSentinelStore.load()
        ui.lastRescue = s.lastRescueAction
        let path = library.storeDir + "/moment.db"
        ui.dbBytes = ((try? FileManager.default
            .attributesOfItem(atPath: path))?[.size]
            as? NSNumber)?.intValue ?? 0
        // S5 消费面：快照环最新（本次启动）与上次
        // 启动两条并列（数据行口径）。
        let ring = RescueLogStore.load()
        ui.snapLatest = ring.last.map(snapSummary) ?? ""
        ui.snapPrev = ring.count >= 2
            ? snapSummary(ring[ring.count - 2]) : ""
    }

    private func snapSummary(_ s: RescueSnapshot)
        -> String {
        "mode=\(s.bootMode) db=\(s.dbBytes) memos="
            + (s.memoCount.map(String.init) ?? "-")
            + " streak=\(s.streak)"
    }

    /// 动作 1：尝试正常启动（S3/S6）。救援层自身不
    /// 新增任何写；随后走常规 load() 语义（含既有
    /// 的待删过期真删、空库写种子——那是正常加载
    /// 本身的既定行为，非救援写面）。
    private func tryNormal() {
        DiagLog.shared.log(.info,
            "RESCUE action normal-retry")
        Library.recordRescueAction("normal-retry")
        DiagLog.shared.log(.info, "RESCUE exit to=normal")
        // 只读态回页后走此路：先复位只读句柄（关
        // 句柄/清副本/清列表），ListView 重建才触
        // 发常规 load()（S4 退出唯一路径的后半程）。
        library.prepareNormalStart()
        library.bootMode = .normal
    }

    /// 动作 3：只读打开资料库（S4）。动作记行在
    /// 前（S6 口径）；成败与模式（direct/copy）由
    /// Library.enterReadOnly 记 RESCUE readonly
    /// open 行。成功即切只读浏览态，不留本页。
    private func openReadonly() {
        DiagLog.shared.log(.info,
            "RESCUE action readonly")
        Library.recordRescueAction("readonly")
        _ = library.enterReadOnly()
    }

    /// 动作 5：清除可再生缓存（S7）。先统计字节、
    /// 记动作行（带清前字节数），再执行清理——清
    /// 单只有 URLCache / Library/Caches / tmp 残
    /// 留三处，绝不含 Application Support 与偏好。
    private func clearCaches() {
        let bytes = RescueCacheCleaner.measure()
        DiagLog.shared.log(.info,
            "RESCUE action cache-clear bytes=\(bytes)")
        Library.recordRescueAction("cache-clear")
        RescueCacheCleaner.clear()
        refreshStatus()
    }

    /// 动作 2：导出诊断（S3/S6）。走 DiagView 同链
    /// 组装 + 哨兵摘要段，系统分享；只读 diag 域，
    /// 不依赖开库。
    private func exportDiag() {
        DiagLog.shared.log(.info, "RESCUE action export")
        Library.recordRescueAction("export")
        let sentinelSection = """
            ==== RESCUE sentinel ====
            prevStep=\(library.prevLaunchStep) \
            streak=\(library.prevLaunchStreak) \
            src=\(safeSource) lastRescue=\(ui.lastRescue)
            """
        if let url = DiagView.buildExportFile(
            library: library,
            extraSections: [sentinelSection]) {
            ui.shareURL = url
        }
    }

    /// S13 动作：检查热修复。双源拉取（第一个成功
    /// 为准），结果落缓存并刷新状态区摘要；下次启
    /// 动判定/guard 消费新缓存。
    private func checkOps() {
        ui.opsBusy = true
        OpsDirectives.shared.fetch {
            DispatchQueue.main.async {
                ui.opsBusy = false
                refreshStatus()
            }
        }
    }

    /// 动作 4：导出备份 ZIP（S3）。库未打开时
    /// exportZip 内部已有 nil 守卫记失败行，此处先
    /// 按置灰口径拦截、不触发假动作。
    private func exportZipAction() {
        guard library.isDbOpen else { return }
        DiagLog.shared.log(.info, "RESCUE action zip")
        Library.recordRescueAction("zip")
        if let url = library.exportZip() {
            ui.shareURL = url
        }
    }
}

// ── 可再生缓存清理（S7，R3）────────────────────
// 清单仅此三处：URLCache 全部缓存响应、
// Library/Caches 目录内容、temporaryDirectory 内
// 容（本 App 导出残留）。绝不含 Application
// Support 全域（资料库/附件/diag 日志）与
// UserDefaults（偏好与哨兵）——本段代码按构造即
// 只引用 cachesDirectory 与 temporaryDirectory。
// 定位：只对缓存损坏型问题有效，是排查项不是修
// 复（与 Web repairBoot 清 SW/缓存的疗效差异已
// 在规格 S7 明示，确认文案同口径）。
enum RescueCacheCleaner {
    private static var cachesDir: String {
        FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0].path
    }

    private static var tmpDir: String {
        FileManager.default.temporaryDirectory.path
    }

    private static func dirBytes(_ path: String) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: path)
        else { return 0 }
        var total: Int64 = 0
        for case let name as String in en {
            let attrs = try? fm.attributesOfItem(
                atPath: path + "/" + name)
            total += (attrs?[.size] as? NSNumber)?
                .int64Value ?? 0
        }
        return total
    }

    /// 清前统计（动作行 bytes= 的口径）。
    static func measure() -> Int64 {
        Int64(URLCache.shared.currentDiskUsage)
            + dirBytes(cachesDir) + dirBytes(tmpDir)
    }

    static func clear() {
        URLCache.shared.removeAllCachedResponses()
        clearContents(cachesDir)
        clearContents(tmpDir)
    }

    private static func clearContents(_ path: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(
            atPath: path)) ?? [] {
            try? fm.removeItem(atPath: path + "/" + name)
        }
    }
}

// ── 看门狗浮条（S8，R3）────────────────────────
// 冷启 12 秒未就绪时由根 ZStack 挂在本页之外
// （正常模式下出条，不依赖安全模式页已构建）。
// 构成对位 Web W3：底部浮卡 + 告知文案 +「进入
// 救援」钮 +「×」关闭钮；应用晚到就绪由根视图
// onChange 自动撤条（Library.dismissWatchdog）。
struct WatchdogBar: View {
    @ObservedObject var library: Library

    var body: some View {
        HStack(spacing: 12) {
            Text(Lang.t("rescue.watchdog_bar"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.textMain)
            Spacer(minLength: 0)
            Button(Lang.t("rescue.enter")) {
                library.enterRescueFromWatchdog()
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(T.accent)
            Button {
                library.dismissWatchdog()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12,
                                  weight: .semibold))
                    .foregroundStyle(T.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard(radius: Radius.panelS)
    }
}
