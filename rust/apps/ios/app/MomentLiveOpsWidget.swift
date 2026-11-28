import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

// Live Activity 扩展呈现（权限/实况批，定案
// impl_ios_entitlements_liveops.md §5.2；按功能
// 针对性样式设计批，定案 impl_liveops_design
// .md）：扩展进程不能联网、不能读语言包——文
// 案全部来自主 App 定格写入的属性（opTitle）
// 与状态（stepLabel），本文件零硬编码语言串。
// 呈现按 kind 分形态（图标/主题色单点 LiveOp
// Style）、phase 参与渲染（终态/等待态以图标
// 与色态覆盖 kind 本体），桥会话（长驻、无确
// 定进度）与一次性操作（有 done/total）分开
// 布局。部署目标 16.0、ActivityKit 16.1+：
// WidgetBundle 以 #available 条件纳入（16.0
// 上扩展为空束，不呈现）。

@main
struct MomentLiveOpsWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            MomentLiveOpsWidget()
        }
        #endif
    }
}

#if canImport(ActivityKit)

// ── 样式单点（扩展自包含）─────────────────────
//
// kind → 图标 + 主题色；phase → 图标/色态覆盖。
// 色取系统语义色族：桥系基调蓝与主 App accent
// （0x007AFF）同族，其余按功能语义分色；扩展
// 跨进程无共享令牌，故在本文件内自包含定义，
// 不回读主 App 的 T 令牌。
@available(iOS 16.1, *)
private enum LiveOpStyle {
    static func kindSymbol(_ kind: LiveOpKind) -> String {
        switch kind {
        case .bridgeOp: return "wrench.and.screwdriver.fill"
        case .scenario: return "checklist"
        case .export: return "square.and.arrow.up.fill"
        case .restore: return "square.and.arrow.down.fill"
        case .bridge: return "antenna.radiowaves.left.and.right"
        }
    }

    static func kindTint(_ kind: LiveOpKind) -> Color {
        switch kind {
        case .bridgeOp: return .indigo
        case .scenario: return .teal
        case .export: return .orange
        case .restore: return .purple
        case .bridge: return .blue
        }
    }

    /// 呈现图标：running 用 kind 本体；waiting /
    /// done / failed 以阶段图标覆盖（终态一眼可
    /// 辨，不依赖步名文案）。
    static func symbol(kind: LiveOpKind,
                       phase: LiveOpPhase) -> String {
        switch phase {
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .waiting: return "pause.circle.fill"
        case .running: return kindSymbol(kind)
        }
    }

    /// 呈现色：running 用 kind 主题色；终态/等待
    /// 态以阶段色覆盖。
    static func tint(kind: LiveOpKind,
                     phase: LiveOpPhase) -> Color {
        switch phase {
        case .done: return .green
        case .failed: return .red
        case .waiting: return .gray
        case .running: return kindTint(kind)
        }
    }
}

/// 图标徽章：圆角方底 + 白色阶段图标，锁屏与
/// 灵动岛展开态共用同一锚点形态。
@available(iOS 16.1, *)
private struct LiveOpBadge: View {
    let kind: LiveOpKind
    let phase: LiveOpPhase
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: LiveOpStyle.symbol(
            kind: kind, phase: phase))
            .font(.system(size: size * 0.52,
                          weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(
                    cornerRadius: size * 0.3,
                    style: .continuous)
                    .fill(LiveOpStyle.tint(
                        kind: kind, phase: phase)))
    }
}

/// 背景/描边着色（16.2+ API，低版本静默回落系
/// 统默认）：锁屏卡以 kind 主题色淡染成卡面，
/// 灵动岛描边（keyline）随阶段色走。
@available(iOS 16.1, *)
private extension View {
    @ViewBuilder
    func liveOpsBackgroundTint(_ color: Color) -> some View {
        if #available(iOS 16.2, *) {
            activityBackgroundTint(color)
        } else {
            self
        }
    }

    @ViewBuilder
    func liveOpsKeylineTint(_ color: Color) -> some View {
        if #available(iOS 16.2, *) {
            keylineTint(color)
        } else {
            self
        }
    }
}

@available(iOS 16.1, *)
struct MomentLiveOpsWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: OpsActivityAttributes.self
        ) { context in
            // 锁屏 / 横幅呈现：徽章锚 + 标题行
            // （右侧：指纹短记优先、否则计数）+
            // 步名 + 进度（确定进度走条、一次性
            // 操作无总数时走不确定条；桥会话无
            // 进度条，状态词即内容）。
            let a = context.attributes
            let s = context.state
            let tint = LiveOpStyle.tint(
                kind: a.opKind, phase: s.phase)
            HStack(alignment: .center, spacing: 12) {
                LiveOpBadge(kind: a.opKind, phase: s.phase)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: 8
                    ) {
                        Text(a.opTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if !a.opDetail.isEmpty {
                            Text(a.opDetail)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let total = s.total,
                                  total > 0 {
                            Text("\(s.done)/\(total)")
                                .font(
                                    .caption
                                        .monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(s.stepLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let total = s.total, total > 0 {
                        ProgressView(
                            value: Double(s.done),
                            total: Double(total))
                            .tint(tint)
                    } else if s.phase == .running
                                && a.opKind != .bridge {
                        ProgressView()
                            .tint(tint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .liveOpsBackgroundTint(
                LiveOpStyle.kindTint(a.opKind).opacity(0.5))
        } dynamicIsland: { context in
            // 灵动岛：展开态三区成卡（leading 徽
            // 章 + 标题、trailing 计数或阶段图标、
            // bottom 步名行 + 进度），治旧版单行
            // 小字读作空黑条；compact 以图标代长
            // 标题；minimal 为 kind/阶段图标。
            let a = context.attributes
            let s = context.state
            let tint = LiveOpStyle.tint(
                kind: a.opKind, phase: s.phase)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        LiveOpBadge(
                            kind: a.opKind, phase: s.phase,
                            size: 30)
                        Text(a.opTitle)
                            .font(.subheadline
                                .weight(.semibold))
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let total = s.total, total > 0 {
                        Text("\(s.done)/\(total)")
                            .font(.headline
                                .monospacedDigit())
                            .foregroundStyle(tint)
                    } else {
                        Image(systemName: LiveOpStyle.symbol(
                            kind: a.opKind, phase: s.phase))
                            .font(.headline)
                            .foregroundStyle(tint)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(s.stepLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if !a.opDetail.isEmpty {
                                Text(a.opDetail)
                                    .font(.caption2
                                        .monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let total = s.total, total > 0 {
                            ProgressView(
                                value: Double(s.done),
                                total: Double(total))
                                .tint(tint)
                        } else if s.phase == .running
                                    && a.opKind != .bridge {
                            ProgressView()
                                .tint(tint)
                        }
                    }
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: LiveOpStyle.symbol(
                    kind: a.opKind, phase: s.phase))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            } compactTrailing: {
                if let total = s.total, total > 0 {
                    Text("\(s.done)/\(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(tint)
                } else if s.phase != .running {
                    Image(systemName: LiveOpStyle.symbol(
                        kind: a.opKind, phase: s.phase))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                } else {
                    EmptyView()
                }
            } minimal: {
                Image(systemName: LiveOpStyle.symbol(
                    kind: a.opKind, phase: s.phase))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
            }
            .liveOpsKeylineTint(tint)
        }
    }
}
#endif
