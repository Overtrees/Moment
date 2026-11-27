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

    final class BridgeSettingsUI: ObservableObject {
        @Published var confirmRevoke = false
    }

    private func scopeName(_ scope: String) -> String {
        Lang.t("bridge.scope_" + scope)
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
                                .font(.system(
                                    size: 16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t("bridge.enable_note"))
                                .font(.system(size: 12))
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
                            .font(.system(
                                size: 16, weight: .semibold))
                            .foregroundStyle(T.textMain)
                        if bridge.recentCalls.isEmpty {
                            Text(Lang.t("bridge.no_calls"))
                                .font(.system(size: 13))
                                .foregroundStyle(T.textSecondary)
                        } else {
                            ForEach(bridge.recentCalls) {
                                call in
                                HStack(spacing: 8) {
                                    Text(call.tool)
                                        .font(.system(size: 13)
                                            .monospaced())
                                        .foregroundStyle(
                                            T.textMain)
                                    Spacer()
                                    Text(call.code)
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            call.code == "ok"
                                            ? T.textSecondary
                                            : T.warning)
                                    Text("\(call.ms)ms")
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            T.textSecondary)
                                    Text(timeText(call.atMs))
                                        .font(.system(size: 12))
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(T.textMain)
                Spacer()
                Text(Lang.t(bridge.linkStateKey))
                    .font(.footnote)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(T.accent)
                    Button(Lang.t("bridge.pair_cancel")) {
                        bridge.cancelPairing()
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(T.warning)
                }
            } else if bridge.isPaired {
                Text(bridge.scopes.isEmpty
                     ? Lang.t("bridge.scope_read")
                     : bridge.scopes.map(scopeName)
                        .joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(T.textSecondary)
                Text(Lang.t("bridge.disconnect_note"))
                    .font(.system(size: 12))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(T.warning)
            } else {
                Text(Lang.t("bridge.unpaired_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(T.textSecondary)
                Button(Lang.t("bridge.pair_start")) {
                    bridge.beginPairing()
                }
                .font(.system(size: 14, weight: .semibold))
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
