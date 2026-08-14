import ActivityKit
import SwiftUI
import WidgetKit

struct FastMapLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastMapActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.categoryTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.state.distanceText)
                            .font(.title3.weight(.bold))
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: "location.north.fill")
                            .foregroundStyle(.blue)
                            .rotationEffect(.degrees(context.state.arrowRotationDegrees))
                            .animation(.smooth(duration: 0.25), value: context.state.arrowRotationDegrees)
                        Text(context.state.directionText)
                            .font(.headline)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.placeName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(context.state.arrowRotationDegrees))
            } compactTrailing: {
                Text(context.state.distanceText)
                    .font(.caption2.weight(.bold))
            } minimal: {
                Image(systemName: "location.fill")
                    .foregroundStyle(.blue)
                    .rotationEffect(.degrees(context.state.arrowRotationDegrees))
            }
            .keylineTint(.blue)
        }
    }
}

private struct LockScreenActivityView: View {
    let state: FastMapActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.blue)
                .rotationEffect(.degrees(state.arrowRotationDegrees))
                .animation(.smooth(duration: 0.25), value: state.arrowRotationDegrees)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.categoryTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(state.placeName)
                    .font(.headline)
                    .lineLimit(1)

                Text("\(state.directionText) · \(state.distanceText)")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
