// ── MCP 桥设置二级页（M1）──
// 设置家族体例：ChromeView + glassCard + 行式布
// 局；开关默认关（UserDefaults bridgeEnabled 缺
// 省 false）。本页承接配对全流程：开始配对后展
// 示设备指纹与授权能力勾选，机主在本页点确认完
// 成配对（配对 App 内确认批起去 Safari 跳转，确
// 认经中继 JSON 通道直达 DO 校验单点）；授权动
// 作始终是机主本人的显式点按，本页不自动完成任
// 何授权（方案授权三道门）。二维码保留为「在另
// 一台设备上确认」的替代通道（同一中继配对页）。

import SwiftUI
import UIKit

struct BridgeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var bridge =
        BridgeCoordinator.shared
    @StateObject private var ui = BridgeSettingsUI()
    // 文字大小跟随系统（Dynamic Type 全量实装，
    // impl_dynamic_type_full）：无语义样式等值的
    // 字号走 ScaledMetric 相对缩放（基准值不变）。
    @ScaledMetric(relativeTo: .body)
    private var f14: CGFloat = 14
    // 语义字体喂点（fix_dynamic_type_follow：
    // relativeTo = 被替样式本身、与 UIFontMetrics
    // 同表）。
    @ScaledMetric(relativeTo: .caption)
    private var f12: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote)
    private var f13: CGFloat = 13
    @ScaledMetric(relativeTo: .callout)
    private var f16: CGFloat = 16
    @ScaledMetric(relativeTo: .title3)
    private var f20: CGFloat = 20

    final class BridgeSettingsUI: ObservableObject {
        @Published var confirmRevoke = false
        /// 待配对授权勾选（配对 App 内确认批）：
        /// read 恒授不入状态；write/ops 默认不
        /// 授，会话更替时经 onChange 复位。
        @Published var grantWrite = false
        @Published var grantOps = false
        /// 密钥卡「已复制」瞬时态（同批）。
        @Published var keyCopied = false
    }

    /// 授权勾选行（配对 App 内确认批）：与设置
    /// 族行式同体例——名 + 说明 + 系统 Toggle；
    /// read 行恒开禁用（必选语义与中继校验单
    /// 点一致：confirm 恒含 read）。
    private func scopeRow(name: String, note: String,
                          isOn: Binding<Bool>,
                          disabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: f14,
                                  weight: .semibold))
                    .foregroundStyle(T.textMain)
                Text(note)
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .disabled(disabled)
        }
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
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t("bridge.enable_note"))
                                .font(.system(size: f12))
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
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(Lang.t("bridge.notify_note"))
                                .font(.system(size: f12))
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
                            .font(.system(size: f16, weight: .semibold))
                            .foregroundStyle(T.textMain)
                        Spacer()
                        Text(bridge.deviceFingerprint ?? "-")
                            .font(.system(size: f13,
                                          design: .monospaced))
                            .foregroundStyle(T.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .glassCard(radius: Radius.panel)
                    .padding(.top, 24)

                    pairingSection
                        .padding(.top, 24)

                    // 客户端密钥卡（配对 App 内确认
                    // 批）：确认成功后一次性显示，密
                    // 钥只在协调器进程内内存中（不落
                    // 盘、不入 Diag）；复制走系统剪贴
                    // 板，点「我已保存」即清
                    // （dismissClientKey 单点）。
                    if let clientKey =
                        bridge.oneTimeClientKey {
                        VStack(alignment: .leading,
                               spacing: 10) {
                            Text(Lang.t("bridge.key_title"))
                                .font(.system(size: f16, weight: .semibold))
                                .foregroundStyle(T.textMain)
                            Text(clientKey)
                                .font(.system(size: f13,
                                              design: .monospaced))
                                .foregroundStyle(T.textMain)
                                .textSelection(.enabled)
                            Text(Lang.t("bridge.key_note"))
                                .font(.system(size: f12))
                                .foregroundStyle(T.textSecondary)
                            HStack(spacing: 16) {
                                Button(ui.keyCopied
                                       ? Lang.t("bridge.key_copied")
                                       : Lang.t("bridge.key_copy")) {
                                    UIPasteboard.general
                                        .string = clientKey
                                    ui.keyCopied = true
                                }
                                .font(.system(size: f14, weight: .semibold))
                                .foregroundStyle(T.accent)
                                Button(Lang.t("bridge.key_saved")) {
                                    bridge.dismissClientKey()
                                    ui.keyCopied = false
                                }
                                .font(.system(size: f14))
                                .foregroundStyle(T.textMain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassCard(radius: Radius.panel)
                        .padding(.top, 24)
                    }

                    // 最近调用（协调器环形留痕，只
                    // 记工具名/结果码/耗时，不记参数
                    // 与结果正文）。
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Lang.t("bridge.recent_calls"))
                            .font(.system(size: f16, weight: .semibold))
                            .foregroundStyle(T.textMain)
                        if bridge.recentCalls.isEmpty {
                            Text(Lang.t("bridge.no_calls"))
                                .font(.system(size: f13))
                                .foregroundStyle(T.textSecondary)
                        } else {
                            ForEach(bridge.recentCalls) {
                                call in
                                HStack(spacing: 8) {
                                    Text(call.tool)
                                        .font(.system(size: f13,
                                                      design: .monospaced))
                                        .foregroundStyle(
                                            T.textMain)
                                    Spacer()
                                    Text(call.code)
                                        .font(.system(size: f12))
                                        .foregroundStyle(
                                            call.code == "ok"
                                            ? T.textSecondary
                                            : T.warning)
                                    Text("\(call.ms)ms")
                                        .font(.system(size: f12))
                                        .foregroundStyle(
                                            T.textSecondary)
                                    Text(timeText(call.atMs))
                                        .font(.system(size: f12))
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
        // 自检驱动注册（U5）：桥设置页结构读
        // （SET-06 抽样）——连接状态/scopes/配对
        // 在位直读协调器；配对/吊销动作本体是
        // 用户显式点按面（人工主），本面不代行。
        .background(UITestAnchor(
            providesFrame: false) {
            UITestSurfaceEntry(
                id: "settings.bridge", kind: "page",
                instance: "-",
                state: [
                    "enabled": {
                        bridge.enabled
                            ? "true" : "false"
                    },
                    "linkState": { bridge.linkState },
                    "paired": {
                        bridge.isPaired
                            ? "true" : "false"
                    },
                    "scopes": {
                        bridge.scopes
                            .sorted()
                            .joined(separator: ",")
                    },
                ])
        })
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
                    .font(.system(size: f20, design: .monospaced)
                        .weight(.semibold))
                    .foregroundStyle(T.textMain)
                Text(Lang.t("bridge.pair_hint"))
                    .font(.system(size: f12))
                    .foregroundStyle(T.textSecondary)
                // 授权勾选（配对 App 内确认批）：与
                // 中继配对页旧表单同语义——read 必
                // 选恒授、write/ops 由机主勾选；确
                // 认时经协调器 confirmPairing 直达
                // 中继同一校验单点，全程不离 App。
                VStack(alignment: .leading, spacing: 8) {
                    scopeRow(
                        name: Lang.t("bridge.scope_read"),
                        note: Lang.t(
                            "bridge.pair_scope_read_note"),
                        isOn: .constant(true),
                        disabled: true)
                    scopeRow(
                        name: Lang.t("bridge.scope_write"),
                        note: Lang.t(
                            "bridge.pair_scope_write_note"),
                        isOn: $ui.grantWrite,
                        disabled: false)
                    scopeRow(
                        name: Lang.t("bridge.scope_ops"),
                        note: Lang.t(
                            "bridge.pair_scope_ops_note"),
                        isOn: $ui.grantOps,
                        disabled: false)
                }
                if bridge.pairConfirming {
                    Text(Lang.t("bridge.pair_waiting"))
                        .font(.system(size: f13))
                        .foregroundStyle(T.textSecondary)
                }
                if let err = bridge.pairConfirmError {
                    Text(Lang.tf(
                        "bridge.pair_confirm_failed",
                        ["error": err]))
                        .font(.system(size: f12))
                        .foregroundStyle(T.warning)
                }
                // 配对二维码（impl_pairing_qr）：与中
                // 继配对页同 URL、同单一构造点，二维
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
                        .font(.system(size: f12))
                        .foregroundStyle(T.textSecondary)
                }
                // 过期呈现：超过 expiresAtMs 改显
                // pair_expired（有效性判据与协调器同
                // 口径：epochMs() > expiresAtMs 即过
                // 期）；该键此前五语有定义、消费面零
                // 引用，被 Web CI 判僵尸键，定补引用
                // 而非删键。未过期形态逐值不变。
                if Library.epochMs() > pending.expiresAtMs {
                    Text(Lang.t("bridge.pair_expired"))
                        .font(.system(size: f12))
                        .foregroundStyle(T.textSecondary)
                } else {
                    Text(Lang.tf("bridge.pair_expires",
                                 ["time": timeText(
                                     pending.expiresAtMs)]))
                        .font(.system(size: f12))
                        .foregroundStyle(T.textSecondary)
                }
                HStack(spacing: 16) {
                    Button(Lang.t("bridge.pair_confirm")) {
                        var sel = ["read"]
                        if ui.grantWrite {
                            sel.append("write")
                        }
                        if ui.grantOps {
                            sel.append("ops")
                        }
                        bridge.confirmPairing(scopes: sel)
                    }
                    .font(.system(size: f14, weight: .semibold))
                    .foregroundStyle(T.accent)
                    .disabled(bridge.pairConfirming
                        || Library.epochMs()
                            > pending.expiresAtMs)
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
        // 待配对会话更替（起新一轮/收敛清除）时勾
        // 选复位（配对 App 内确认批）：授权勾选只
        // 属于其所属会话，不跨轮残留。
        .onChange(of: bridge.pendingPairing?.id) { _ in
            ui.grantWrite = false
            ui.grantOps = false
        }
    }
}
