import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

// Live Activity 扩展呈现（权限/实况批，定案
// impl_ios_entitlements_liveops.md §5.2）：扩展进程
// 不能联网、不能读语言包——文案全部来自主 App 定格
// 写入的属性（opTitle）与状态（stepLabel），本文件
// 零硬编码语言串，只做布局与进度呈现。部署目标
// 16.0、ActivityKit 16.1+：WidgetBundle 以
// #available 条件纳入（16.0 上扩展为空束，不呈现）。

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
@available(iOS 16.1, *)
struct MomentLiveOpsWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: OpsActivityAttributes.self
        ) { context in
            // 锁屏 / 横幅呈现：标题 + 阶段步名 + 进度。
            // opDetail 非空时（桥会话的指纹短记）同行
            // 右侧小字呈现；操作类恒空、呈现与旧版同。
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.attributes.opTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    if !context.attributes.opDetail
                        .isEmpty {
                        Text(context.attributes.opDetail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(context.state.stepLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let total = context.state.total,
                   total > 0 {
                    ProgressView(
                        value: Double(context.state.done),
                        total: Double(total))
                }
            }
            .padding(12)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.opTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let total = context.state.total,
                       total > 0 {
                        Text("\(context.state.done)/\(total)")
                            .font(.caption.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.stepLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Text(context.attributes.opTitle)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 72, alignment: .leading)
            } compactTrailing: {
                if let total = context.state.total,
                   total > 0 {
                    Text("\(context.state.done)/\(total)")
                        .font(.caption2.monospacedDigit())
                }
            } minimal: {
                Circle()
                    .frame(width: 6, height: 6)
            }
        }
    }
}
#endif
