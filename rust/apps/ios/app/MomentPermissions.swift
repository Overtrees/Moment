// 权限中心（设置页子页，impl_permission_center.md）：
// 声明矩阵（impl_ios_entitlements_liveops.md 31 行）
// 的运行时收口。此前 B 段只落声明与嵌入，多数声明
// 没有对应的运行时请求代码路径，用户在真机上看不
// 到任何权限请求。本文件逐项：
// - 状态向系统真读（各框架 authorizationStatus /
//   等价读面），不推断、不缓存造假；
// - 可请求的走各自框架正道 API（点按才请求，禁止
//   启动/进页自动索取，与 §3.4 口径一致）；
// - 本地网络无状态/请求 API：以 Bonjour 浏览探针
//   （Network 框架浏览器）触发系统弹窗，探针结果如实
//   呈现（探针口径在行注与报告中写明，不冒充系统
//   状态接口）；
// - 实况无弹窗：只读启用状态 + 系统
//   设置深链（深链仅此一类）；
// - 无授权面的已声明能力（后台任务 / 远程推送环
//   境）如实标「已声明」，无功能使用的在行注写明。
// 既有惰性请求点（天气定位链、桥设置页通知开关）
// 保持不动，本页不重复造请求路径、已授权项点按
// 无副作用。
import SwiftUI
import UIKit
import CoreLocation
import AVFoundation
import Photos
import LocalAuthentication
import UserNotifications
import EventKit
import Network
#if canImport(ActivityKit)
import ActivityKit
#endif

/// 权限项全集（与报告三态表逐行对应）。grant 组
/// 进「需要授权」节，declared 组进「已声明的能力」
/// 节（无用户授权面，只显已声明状态）。
enum PermKind: String, CaseIterable {
    case notifications, location, camera, photoRead,
         photoAdd, microphone, faceID, localNetwork,
         calendar, reminders, liveActivities
    case background, pushEnv

    static let grantKinds: [PermKind] = [
        .notifications, .location, .camera, .photoRead,
        .photoAdd, .microphone, .faceID, .localNetwork,
        .calendar, .reminders, .liveActivities,
    ]
    static let declaredKinds: [PermKind] = [
        .background, .pushEnv,
    ]

    /// Diag 打点 token（不本地化，与 SET 域口径同）。
    var token: String {
        switch self {
        case .notifications: return "notifications"
        case .location: return "location"
        case .camera: return "camera"
        case .photoRead: return "photo_read"
        case .photoAdd: return "photo_add"
        case .microphone: return "microphone"
        case .faceID: return "faceid"
        case .localNetwork: return "local_network"
        case .calendar: return "calendar"
        case .reminders: return "reminders"
        case .liveActivities: return "live_activities"
        case .background: return "background"
        case .pushEnv: return "push_env"
        }
    }

    var titleKey: String { "perm.item_" + token }
    var noteKey: String { "perm.note_" + token }

    /// 行图标（SF Symbol，设置族行图标体系）：优先
    /// 取全 App 已在用的符号（相册两项、清单、定位
    /// 均有现行使用点），余为部署目标（16.0）内长
    /// 期可用的系统符号，与各项系统设置面语义对应。
    var icon: String {
        switch self {
        case .notifications: return "bell.badge"
        case .location: return "location"
        case .camera: return "camera"
        case .photoRead: return "photo.on.rectangle.angled"
        case .photoAdd: return "photo.badge.plus"
        case .microphone: return "mic"
        case .faceID: return "faceid"
        case .localNetwork: return "network"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .liveActivities: return "timer"
        case .background: return "arrow.triangle.2.circlepath"
        case .pushEnv: return "paperplane"
        }
    }

    /// 请求钮可见性（状态相关部分在 PermCenter 侧
    /// 的当前状态上判）：本类是否具备请求面。
    var hasRequestSurface: Bool {
        switch self {
        case .background, .pushEnv, .liveActivities:
            return false
        default:
            return true
        }
    }

    /// 行注是否为「暂无功能使用」类（与五语
    /// perm.note_* 现行文案逐项对应：九项的注即
    /// 该句、文案逐字不动；余四项为功能说明、
    /// 恒显）。本类行注的显示条件见
    /// PermissionsView.showsNote（用户 2026-11-28
    /// 装机反馈改判：未请求态不显、请求后才显）。
    var noteIsNoFeature: Bool {
        switch self {
        case .calendar, .camera, .faceID, .localNetwork,
             .microphone, .photoAdd, .photoRead, .pushEnv,
             .reminders:
            return true
        default:
            return false
        }
    }
}

/// 授权状态（呈现与 Diag 共用一套枚举，token 为
/// Diag result 值、langKey 为呈现文案键）。
enum PermStatus {
    case granted, denied, restricted, notDetermined
    case writeOnly, enabled, disabled, declared
    case available, unavailable
    case unknown, probing, inconclusive, lanOK

    var token: String {
        switch self {
        case .granted: return "granted"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "not_determined"
        case .writeOnly: return "write_only"
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .declared: return "declared"
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        case .probing: return "probing"
        case .inconclusive: return "inconclusive"
        case .lanOK: return "lan_ok"
        }
    }

    var langKey: String { "perm.status_" + token }
}

/// 权限状态真读 + 请求分发单点。全 App 唯一的权
/// 限请求面（既有天气定位/桥通知开关是各自功能内
/// 的惰性点，不经此处、保持不动）。
final class PermCenter: NSObject, ObservableObject,
    CLLocationManagerDelegate {
    @Published var statuses: [PermKind: PermStatus] = [:]

    private let locManager = CLLocationManager()
    private let eventStore = EKEventStore()
    private var locRequestPending = false
    private var lanBrowser: NWBrowser?
    private var lanTimeout: DispatchWorkItem?

    override init() {
        super.init()
        locManager.delegate = self
    }

    // ── 状态真读 ─────────────────────────────────

    /// 逐项重读（进页 / 回前台 / 请求回调共用）。
    /// 本地网络不在此列：无状态接口，其状态只由
    /// 探针推进（未探针时呈现「未检测」）。
    func refreshAll() {
        for kind in PermKind.allCases
        where kind != .localNetwork {
            refreshOne(kind)
        }
        UNUserNotificationCenter.current()
            .getNotificationSettings { [weak self] s in
                self?.apply(.notifications,
                            Self.mapNotify(
                                s.authorizationStatus),
                            log: false)
            }
    }

    private func refreshOne(_ kind: PermKind) {
        switch kind {
        case .notifications:
            // 异步读面，走 refreshAll 的专用回调。
            break
        case .location:
            apply(kind, Self.mapLocation(
                locManager.authorizationStatus), log: false)
        case .camera:
            let st = AVCaptureDevice.authorizationStatus(for: .video)
            apply(kind, Self.mapAV(st), log: false)
        case .photoRead:
            let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            apply(kind, Self.mapPhoto(st), log: false)
        case .photoAdd:
            let st = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            apply(kind, Self.mapPhoto(st), log: false)
        case .microphone:
            apply(kind, micStatus(), log: false)
        case .faceID:
            apply(kind, faceIDStatus(), log: false)
        case .localNetwork:
            break
        case .calendar:
            apply(kind, Self.mapEventKit(
                EKEventStore.authorizationStatus(
                    for: .event)), log: false)
        case .reminders:
            apply(kind, Self.mapEventKit(
                EKEventStore.authorizationStatus(
                    for: .reminder)), log: false)
        case .liveActivities:
            apply(kind, liveStatus(), log: false)
        case .background, .pushEnv:
            apply(kind, .declared, log: false)
        }
    }

    private func micStatus() -> PermStatus {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared
                .recordPermission {
            case .undetermined: return .notDetermined
            case .denied: return .denied
            case .granted: return .granted
            @unknown default: return .notDetermined
            }
        }
        switch AVAudioSession.sharedInstance()
            .recordPermission {
        case .undetermined: return .notDetermined
        case .denied: return .denied
        case .granted: return .granted
        @unknown default: return .notDetermined
        }
    }

    private func faceIDStatus() -> PermStatus {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &err)
        return ok ? .available : .unavailable
    }

    private func liveStatus() -> PermStatus {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo()
                .areActivitiesEnabled
                ? .enabled : .disabled
        }
        #endif
        return .unavailable
    }

    // ── 状态映射（框架枚举 → PermStatus） ────────

    static func mapNotify(
        _ s: UNAuthorizationStatus) -> PermStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral:
            return .granted
        @unknown default: return .notDetermined
        }
    }

    static func mapLocation(
        _ s: CLAuthorizationStatus) -> PermStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        @unknown default: return .notDetermined
        }
    }

    static func mapAV(
        _ s: AVAuthorizationStatus) -> PermStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .granted
        @unknown default: return .notDetermined
        }
    }

    /// .limited（用户只开放部分照片）折入 granted：
    /// 行注不宣称全库访问，状态词只表「已获授权」。
    static func mapPhoto(
        _ s: PHAuthorizationStatus) -> PermStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized, .limited: return .granted
        @unknown default: return .notDetermined
        }
    }

    static func mapEventKit(
        _ s: EKAuthorizationStatus) -> PermStatus {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        default:
            if #available(iOS 17.0, *),
               s == .writeOnly {
                return .writeOnly
            }
            return .granted
        }
    }

    // ── 请求分发 ─────────────────────────────────

    /// 请求钮点按的唯一入口。已授权项在 View 侧不
    /// 出钮（点按无副作用的口径由可见性保证）；本
    /// 函数只对未定/可重探状态有实际动作。
    func request(_ kind: PermKind) {
        switch kind {
        case .notifications:
            UNUserNotificationCenter.current()
                .requestAuthorization(
                    options: [.alert, .sound, .badge]
                ) { [weak self] _, _ in
                    self?.finishRequest(kind)
                }
        case .location:
            locRequestPending = true
            locManager.requestWhenInUseAuthorization()
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                self?.finishRequest(kind)
            }
        case .photoRead:
            PHPhotoLibrary.requestAuthorization(
                for: .readWrite) { [weak self] _ in
                    self?.finishRequest(kind)
                }
        case .photoAdd:
            PHPhotoLibrary.requestAuthorization(
                for: .addOnly) { [weak self] _ in
                    self?.finishRequest(kind)
                }
        case .microphone:
            if #available(iOS 17.0, *) {
                AVAudioApplication
                    .requestRecordPermission {
                        [weak self] _ in
                        self?.finishRequest(kind)
                    }
            } else {
                AVAudioSession.sharedInstance()
                    .requestRecordPermission {
                        [weak self] _ in
                        self?.finishRequest(kind)
                    }
            }
        case .faceID:
            // Face ID 无独立「请求授权」API：首次
            // 评估调用即系统同意弹窗的触发
            // 面（NSFaceIDUsageDescription 已声明）。
            // 本次评估只为触发/确认授权，不读取任
            // 何评估结果之外的信息。
            let ctx = LAContext()
            ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: Lang.t(
                    "perm.faceid_reason")
            ) { [weak self] _, _ in
                self?.finishRequest(kind)
            }
        case .localNetwork:
            probeLocalNetwork()
        case .calendar:
            if #available(iOS 17.0, *) {
                eventStore.requestFullAccessToEvents {
                    [weak self] _, _ in
                    self?.finishRequest(kind)
                }
            } else {
                eventStore.requestAccess(to: .event) {
                    [weak self] _, _ in
                    self?.finishRequest(kind)
                }
            }
        case .reminders:
            if #available(iOS 17.0, *) {
                eventStore.requestFullAccessToReminders {
                    [weak self] _, _ in
                    self?.finishRequest(kind)
                }
            } else {
                eventStore.requestAccess(to: .reminder) {
                    [weak self] _, _ in
                    self?.finishRequest(kind)
                }
            }
        case .liveActivities, .background, .pushEnv:
            break
        }
    }

    /// 请求收口：重读该项状态并记一行 Diag（权限
    /// 名 + 结果状态，不记任何敏感值）。定位走委
    /// 托回调（见 locationManagerDidChangeAuth-
    /// orization），不经此处。
    private func finishRequest(_ kind: PermKind) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshOne(kind)
            if let s = self.statuses[kind] {
                DiagLog.shared.log(.info,
                    "SET perm request kind=\(kind.token)"
                    + " result=\(s.token)")
            }
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager) {
        let s = Self.mapLocation(
            manager.authorizationStatus)
        apply(.location, s, log: false)
        if locRequestPending, s != .notDetermined {
            locRequestPending = false
            DiagLog.shared.log(.info,
                "SET perm request kind=location"
                + " result=\(s.token)")
        }
    }

    // ── 本地网络探针（Bonjour 浏览） ─────────────
    // iOS 无本地网络的状态查询/请求 API：浏览我方
    // 自有服务类型（NSBonjourServices 已声明）即
    // 触发系统弹窗。读回口径：浏览器达 .ready 或
    // 收到结果 = 浏览可用；策略拒绝错误（kDNS-
    // ServiceErr_PolicyDenied）= 已拒绝；8 秒内
    // 无定论 = 未能确定。这是探针结果、不是系统
    // 状态接口，行注已写明。

    private func probeLocalNetwork() {
        if statuses[.localNetwork] == .probing { return }
        apply(.localNetwork, .probing, log: false)
        let browser = NWBrowser(
            for: .bonjour(type: "_moment._tcp",
                          domain: nil),
            using: NWParameters())
        lanBrowser = browser
        browser.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.finishLan(.lanOK)
            case .waiting(let err), .failed(let err):
                if Self.isPolicyDenied(err) {
                    self.finishLan(.denied)
                } else if case .failed(_) = st {
                    self.finishLan(.inconclusive)
                }
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = {
            [weak self] results, _ in
            if !results.isEmpty {
                self?.finishLan(.lanOK)
            }
        }
        browser.start(queue: .main)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self,
                  self.statuses[.localNetwork] == .probing
            else { return }
            self.finishLan(.inconclusive)
        }
        lanTimeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 8, execute: timeout)
    }

    private func finishLan(_ status: PermStatus) {
        guard statuses[.localNetwork] == .probing
        else { return }
        lanTimeout?.cancel()
        lanTimeout = nil
        lanBrowser?.cancel()
        lanBrowser = nil
        apply(.localNetwork, status, log: true)
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        // kDNSServiceErr_PolicyDenied 的错误码字面。
        if case .dns(let code) = error {
            return code == -65570
        }
        return false
    }

    // ── 状态写入（主线程收口） ───────────────────

    private func apply(_ kind: PermKind,
                       _ status: PermStatus,
                       log: Bool) {
        let write = { [weak self] in
            guard let self else { return }
            self.statuses[kind] = status
            if log {
                DiagLog.shared.log(.info,
                    "SET perm request kind=\(kind.token)"
                    + " result=\(status.token)")
            }
        }
        if Thread.isMainThread {
            write()
        } else {
            DispatchQueue.main.async(execute: write)
        }
    }
}

// ── 权限页（设置族：ChromeView + settingsContent-
// Frame + SetRow 家族行形态；呈现/交互细节经
// fix_permissions_uiux 按设置族口径调优：图标列、
// 行距、状态色分组、胶囊标示、整行命中、切换
// 过渡——功能与状态口径零改动） ────────────────
struct PermissionsView: View {
    @EnvironmentObject private var langStore: LangStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var center = PermCenter()
    // 语义字体喂点（fix_dynamic_type_follow：
    // relativeTo = 被替样式本身、与 UIFontMetrics
    // 同表）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16

    var body: some View {
        ChromeView(title: Lang.t("perm.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Lang.t("perm.intro"))
                        .font(.system(size: f12))
                        // 长文行距（手势页 12pt 说明
                        // 6.6 口径 = 0.55 倍字号，写成
                        // 喂点倍数随 DT 缩放）。
                        .lineSpacing(f12 * 0.55)
                        .foregroundStyle(T.textSecondary)
                        .padding(.horizontal, 4)
                    SectionHeader(
                        text: Lang.t("perm.section_grant"),
                        topPad: 24)
                    card(PermKind.grantKinds)
                    SectionHeader(
                        text: Lang.t(
                            "perm.section_declared"),
                        topPad: 32)
                    card(PermKind.declaredKinds)
                }
                .settingsContentFrame()
            }
        }
        .onAppear {
            DiagLog.shared.log(.info,
                "SET permissions enter")
            center.refreshAll()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                center.refreshAll()
            }
        }
    }

    private func card(_ kinds: [PermKind]) -> some View {
        VStack(spacing: 0) {
            ForEach(kinds.indices, id: \.self) { idx in
                if idx > 0 { rowDivider }
                row(kinds[idx])
            }
        }
        .glassCard(radius: Radius.panel)
    }

    /// 行形态（fix_permissions_uiux，对齐设置族）：
    /// 图标列走 SetRow 形态（槽 24、字形封顶、
    /// accent、spacing 11）；有动作的行整行成钮
    /// （SetRow 式 RowPressStyle + contentShape，
    /// 命中区 = 整行），胶囊只是行内的动作标示、
    /// 不再自成小钮；无动作行保持静态呈现。
    @ViewBuilder
    private func row(_ kind: PermKind) -> some View {
        let status = center.statuses[kind] ?? .unknown
        if let act = rowAction(kind, status) {
            Button(action: act) {
                rowContent(kind, status)
            }
            .buttonStyle(RowPressStyle(radius: 0))
        } else {
            rowContent(kind, status)
        }
    }

    /// 行动作收口：可请求态走 PermCenter.request、
    /// 实况走系统设置深链（全 App 仅此一类，PC44-4
    /// 口径不变）；余状态（已授权/已拒绝/已声明/
    /// 探针进行中）无动作、整行不可点。
    private func rowAction(_ kind: PermKind,
                           _ status: PermStatus)
        -> (() -> Void)? {
        if kind == .liveActivities {
            return { openAppSettings() }
        }
        guard showsRequest(kind, status) else {
            return nil
        }
        return { center.request(kind) }
    }

    private func rowContent(_ kind: PermKind,
                            _ status: PermStatus)
        -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: kind.icon)
                // 字形封顶（SetRow 同式）：大字号档
                // 字形溢出 24 槽压标题，封顶至槽宽，
                // 默认档逐值不变。
                .font(.system(size: min(f16, 24)))
                .foregroundStyle(T.accent)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(Lang.t(kind.titleKey))
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textMain)
                if showsNote(kind, status) {
                    Text(Lang.t(kind.noteKey))
                        .font(.system(size: f12))
                        // 长注行距（手势页说明口径，
                        // 0.55 倍字号随 DT 缩放）。
                        .lineSpacing(f12 * 0.55)
                        .foregroundStyle(T.glassLabel)
                }
            }
            Spacer()
            trailing(kind, status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        // 状态切换过渡（全家 0.15 easeOut 惯例）：
        // 状态词更替与胶囊出入不再硬切，通知状态
        // 异步到达的一拍跳变同受此缓动收口。
        .animation(.easeOut(duration: 0.15),
                   value: status)
    }

    @ViewBuilder
    private func trailing(_ kind: PermKind,
                            _ status: PermStatus)
        -> some View {
        HStack(spacing: 10) {
            Text(Lang.t(status.langKey))
                // 状态词（语言页状态口径）：12pt
                // 常规字重的信息呈现，着色只表状态
                // 分组、不作操作强调（操作在胶囊）。
                .font(.system(size: f12))
                .foregroundStyle(statusTint(status))
            if showsRequest(kind, status) {
                pillLabel(Lang.t("perm.request"))
            }
            if kind == .liveActivities {
                pillLabel(Lang.t("perm.open_settings"))
            }
        }
    }

    /// 行注显示条件（用户 2026-11-28 装机反馈改
    /// 判）：功能说明注恒显；「暂无功能使用」注
    /// （noteIsNoFeature）未请求态不显、被请求过
    /// （状态进入请求后结果集）才显，文案逐字不
    /// 动。结果集逐项按各框架状态面定：
    /// - 标准授权面（日历/相机/麦克风/相册读/相
    ///   册存/提醒）：已授权/已拒绝/受限制/仅写
    ///   入；未请求（.notDetermined）与未读到
    ///   （.unknown）不显；
    /// - 本地网络：探针即请求面，未探针
    ///   （.unknown）不显，探针启动后（检测中/
    ///   浏览可用/已拒绝/未能确定）显；
    /// - Face ID：无未定态，出钮条件「不可用」
    ///   即其未请求等值态（showsRequest 同口
    ///   径），不显；可用才显；
    /// - 远程推送（pushEnv）：无请求面、行无交
    ///   互，「被请求过」永不成立，恒不显（取舍
    ///   与理由见 fix_permissions_feedback63.md）。
    private func showsNote(_ kind: PermKind,
                           _ status: PermStatus) -> Bool {
        guard kind.noteIsNoFeature else { return true }
        switch kind {
        case .localNetwork:
            return status != .unknown
        case .faceID:
            return status == .available
        case .pushEnv:
            return false
        default:
            switch status {
            case .granted, .denied, .restricted, .writeOnly:
                return true
            default:
                return false
            }
        }
    }

    /// 请求钮可见性：未定状态才出（已授权/已拒绝
    /// 不出钮——系统不会再弹，点按无意义）；Face
    /// ID 以「不可用」为出钮条件（不可用含未定同
    /// 意，评估即触发面）；本地网络恒可重探（探针
    /// 进行中除外）。
    private func showsRequest(_ kind: PermKind,
                              _ status: PermStatus)
        -> Bool {
        guard kind.hasRequestSurface else { return false }
        switch kind {
        case .faceID:
            return status == .unavailable
        case .localNetwork:
            return status != .probing
        default:
            return status == .notDetermined
        }
    }

    /// 状态着色（fix_permissions_uiux 改判 impl_
    /// permission_center §五的强调色口径）：可用态
    /// 走成功令牌单点（--color-success；原 accent
    /// 蓝与操作标示同色、整列已授权时读作链接）；
    /// 受阻态（已拒绝/受限制）统一警告色（原受限
    /// 制落次级、与已拒绝同为受阻却分色含糊）；
    /// 余（未请求/未检测/检测中/未能确定/已关
    /// 闭/已声明/不可用）皆次级。状态真值不变，
    /// 只改呈现分组。
    private func statusTint(_ status: PermStatus)
        -> Color {
        switch status {
        case .granted, .enabled, .available, .lanOK,
             .writeOnly:
            return T.success
        case .denied, .restricted:
            return T.warning
        default:
            return T.textSecondary
        }
    }

    /// 动作胶囊标示（DiagView 胶囊钮口径）：13pt
    /// 常规字重、主文字色、内距 16/10、玻璃胶囊
    /// 面。本体不是按钮——点按由整行钮承接（行
    /// 形态注见 row），此处只作动作可达性的视觉
    /// 标示，形态与 DiagView 的可点胶囊逐值一致。
    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: f13))
            .foregroundStyle(T.textMain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassControl(radius: Radius.pill)
    }

    /// 系统设置深链（仅实况一类：其开关只在系统
    /// 设置内，App 内无可用的请求/切换 API）。
    private func openAppSettings() {
        if let url = URL(string:
            UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(T.borderSoft)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
