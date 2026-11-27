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
// R2 附着点：只读打开资料库（动作 3，S4——FFI
// openReadonly + 门面拒写 + 只读横幅，键
// rescue.open_readonly / rescue.readonly_banner
// / rescue.readonly_write_blocked 已备）。
// R3 附着点：清除可再生缓存（动作 5，S7——键
// rescue.cache_clear / rescue.cache_clear_confirm
// 已备）；看门狗浮条（S8，键 rescue.watchdog_bar
// / rescue.enter 已备）；状态快照环（S5）。
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
                    .glassCard(radius: 20)
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
                    if !ui.lastRescue.isEmpty {
                        statusRow("lastRescue",
                                  ui.lastRescue)
                    }
                }
                .frame(maxWidth: .infinity,
                       alignment: .leading)
                .padding(16)
                .glassCard(radius: 20)
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
                }
                .glassCard(radius: 28)
                .padding(.top, 16)
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
        library.bootMode = .normal
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
