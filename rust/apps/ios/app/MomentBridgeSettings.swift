// ── MCP 桥设置二级页（M1）──
// 设置家族体例：ChromeView + glassCard + 行式布
// 局；开关默认关（UserDefaults bridgeEnabled 缺
// 省 false）。本页承接配对流程的 App 侧一半：开
// 始配对后展示设备指纹与配对页入口，用户在中继
// 配对页核对指纹并确认——授权动作在用户手里，
// 本页不替用户完成任何授权（方案授权三道门）。

import SwiftUI

struct BridgeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var bridge =
        BridgeCoordinator.shared
    @StateObject private var ui = BridgeSettingsUI()
    // 文字大小跟随系统（Dynamic Type 全量实装，
    // impl_dynamic_type_full）：无语义样式等值的
    // 字号走 ScaledMetric 相对缩放（基准值不变）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14

    final class BridgeSettingsUI: ObservableObject {
        @Published var confirmRevoke = false
    }

    private func scopeName(_ scope: String) -> String {
        Lang.t("bridge.scope_" + scope)
    }

    /// 吊销回执文案键映射（桥呈现小批 ①）：回执
    /// 状态源在协调器 revokeOutcome，本页只映射
    /// 呈现；未确认的警示色在渲染点按态取。
    private func revokeOutcomeKey(
        _ outcome: BridgeRevokeOutcome) -> String {
        switch outcome {
        case .pending: return "bridge.revoke_pending"
        case .confirmed: return "bridge.revoke_confirmed"
        case .unconfirmed:
            return "bridge.revoke_unconfirmed"
        }
    }

    private var timeText: (Int64) -> String {
        { ms in
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(
                from: Date(timeIntervalSince1970:
                    Double(ms) / 1000))
        }
    }

    var body: some View {
        ChromeView(title: Lang.t("bridge.title"),
                   onBack: { dismiss() }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 开关卡：系统 Toggle（行为等价、
                    // 系统更优口径），默认关。
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading,
                               spacing: 4) {
                            Text(Lang.t("bridge.enable"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t("bridge.enable_note"))
                                .font(.caption)
                                .foregroundStyle(T.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { bridge.enabled },
                            set: { bridge.setEnabled($0) }))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.panel)

                    // 通知开关（权限批 §3.4）：开启时才
                    // 请求通知授权（禁止启动时索取）；
                    // 与实况共用此偏好面。
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading,
                               spacing: 4) {
                            Text(Lang.t("bridge.notify"))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t("bridge.notify_note"))
                                .font(.caption)
                                .foregroundStyle(T.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { MomentLiveOps.notifyEnabled },
                            set: { MomentLiveOps.setNotifyEnabled($0) }))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.panel)
                    .padding(.top, 24)

                    // 状态行：当前链路状态（本地化
                    // 状态文案与设置主页桥行 meta 同源）。
                    HStack {
                        Text(Lang.t("bridge.fingerprint"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(T.textMain)
                        Spacer()
                        Text(bridge.deviceFingerprint ?? "-")
                            .font(.system(.footnote,
                                          design: .monospaced))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.panel)
                    .padding(.top, 24)

                    pairingSection
                        .padding(.top, 24)

                    // 最近调用（协调器环形留痕，只
                    // 记工具名/结果码/耗时，不记参数
                    // 与结果正文）。
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Lang.t("bridge.recent_calls"))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(T.textMain)
                        if bridge.recentCalls.isEmpty {
                            Text(Lang.t("bridge.no_calls"))
                                .font(.footnote)
                                .foregroundStyle(T.textSecondary)
                        } else {
                            ForEach(bridge.recentCalls) {
                                call in
                                HStack(spacing: 8) {
                                    Text(call.tool)
                                        .font(.system(.footnote,
                                                      design: .monospaced))
                                        .foregroundStyle(
                                            T.textMain)
                                    Spacer()
                                    Text(call.code)
                                        .font(.caption)
                                        .foregroundStyle(
                                            call.code == "ok"
                                            ? T.textSecondary
                                            : T.warning)
                                    Text("\(call.ms)ms")
                                        .font(.caption)
                                        .foregroundStyle(
                                            T.textSecondary)
                                    Text(timeText(call.atMs))
                                        .font(.caption)
                                        .foregroundStyle(
                                            T.textSecondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.panel)
                    .padding(.top, 24)
                }
                .settingsContentFrame()
            }
        }
        .onAppear {
            DiagLog.shared.log(.info, "SET bridge enter")
            // 进页校准：配对状态以中继事实为准，
            // 不等前台轮询窗口（定案
            // fix_bridge_pairing_state.md）。
            bridge.revalidatePairing()
        }
        .onDisappear {
            ui.confirmRevoke = false
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Lang.t("bridge.scopes"))
                    .font(.system(size: f16, weight: .semibold))
                    .foregroundStyle(T.textMain)
                Spacer()
                Text(Lang.t(bridge.linkStateKey))
                    .font(.system(size: f13))
                    .foregroundStyle(T.textSecondary)
            }
            // 断开原因行（桥呈现小批 ③）：映射派
            // 生在协调器 stateReasonKey（仅
            // backoff/connecting 带因），本页只渲
            // 染、有值才显；主页桥行维持只显状态
            // 词，判读面收敛在本页。
            if let reasonKey = bridge.stateReasonKey {
                Text(Lang.t(reasonKey))
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
            }
            if let pending = bridge.pendingPairing {
                Text(pending.fingerprint)
                    .font(.system(.title3, design: .monospaced)
                        .weight(.semibold))
                    .foregroundStyle(T.textMain)
                Text(Lang.t("bridge.pair_hint"))
                    .font(.caption)
                    .foregroundStyle(T.textSecondary)
                Text(Lang.t("bridge.pair_waiting"))
                    .font(.footnote)
                    .foregroundStyle(T.textSecondary)
                // 配对二维码（impl_pairing_qr）：与下
                // 方链接钮同 URL、同单一构造点，二维
                // 码只是把链接送达另一台设备的通道；
                // 白底板是深色模式下可扫性的功能要
                // 求，非装饰。
                if let url = bridge.pairingURL(),
                   let qr = makePairingQRImage(url.absoluteString) {
                    Image(uiImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 148, height: 148)
                        .padding(10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(
                            cornerRadius: Radius.controlS))
                    Text(Lang.t("bridge.pair_qr_hint"))
                        .font(.caption)
                        .foregroundStyle(T.textSecondary)
                }
                Text(Lang.tf("bridge.pair_expires",
                             ["time": timeText(
                                 pending.expiresAtMs)]))
                    .font(.caption)
                    .foregroundStyle(T.textSecondary)
                HStack(spacing: 16) {
                    Button(Lang.t("bridge.pair_open")) {
                        if let url = bridge.pairingURL() {
                            openURL(url)
                        }
                    }
                    .font(.system(size: f14, weight: .semibold))
                    .foregroundStyle(T.accent)
                    Button(Lang.t("bridge.pair_cancel")) {
                        bridge.cancelPairing()
                    }
                    .font(.system(size: f14))
                    .foregroundStyle(T.warning)
                }
            } else if bridge.isPaired {
                // scopes 呈现（桥呈现小批 ②）：空
                // 集是「未回带授权」的未知态，显
                // scopes_none、不再兜底断言成只
                // 读；非空显已授名，其下未授负向行
                // （派生在协调器 ungrantedScopes，
                // 本页不做集合运算）。
                if bridge.scopes.isEmpty {
                    Text(Lang.t("bridge.scopes_none"))
                        .font(.system(size: f13))
                        .foregroundStyle(T.textSecondary)
                } else {
                    Text(bridge.scopes.map(scopeName)
                        .joined(separator: " · "))
                        .font(.system(size: f13))
                        .foregroundStyle(T.textSecondary)
                    if !bridge.ungrantedScopes.isEmpty {
                        Text(Lang.tf(
                            "bridge.scopes_ungranted",
                            ["names": bridge
                                .ungrantedScopes
                                .map(scopeName)
                                .joined(separator: " · ")]))
                            .font(.system(size: f12))
                            .foregroundStyle(T.textSecondary)
                    }
                }
                Text(Lang.t("bridge.disconnect_note"))
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
                Button(ui.confirmRevoke
                       ? Lang.t("bridge.disconnect") + "?"
                       : Lang.t("bridge.disconnect")) {
                    if ui.confirmRevoke {
                        bridge.disconnectAndRevoke()
                        ui.confirmRevoke = false
                    } else {
                        ui.confirmRevoke = true
                    }
                }
                .font(.system(size: f14, weight: .semibold))
                .foregroundStyle(T.warning)
            } else {
                // 吊销回执行（桥呈现小批 ①）：协调
                // 器 revokeOutcome 有值才显（本次
                // 吊销动作的回执，起新配对/配对成
                // 功时已清）；未确认以 warning 色如
                // 实示警，不粉饰为断开干净。
                if let outcome = bridge.revokeOutcome {
                    Text(Lang.t(revokeOutcomeKey(outcome)))
                        .font(.system(size: f12))
                        .foregroundStyle(
                            outcome == .unconfirmed
                            ? T.warning : T.textSecondary)
                }
                Text(Lang.t("bridge.unpaired_note"))
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
                Button(Lang.t("bridge.pair_start")) {
                    bridge.beginPairing()
                }
                .font(.system(size: f14, weight: .semibold))
                .foregroundStyle(T.accent)
                .disabled(!bridge.enabled
                          || bridge.opsDisabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassCard(radius: Radius.panel)
    }
}
