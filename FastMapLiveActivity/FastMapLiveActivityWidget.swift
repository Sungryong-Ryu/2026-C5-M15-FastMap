import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct FastMapLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastMapActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(TossWidgetColor.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                // 확장 영역은 좌우 끝과 아래쪽 모서리 곡률이 커서, 기본 여백만으로는
                // 아이콘과 글자가 잘립니다. contentMargins로 안전 여백을 넉넉히 잡습니다.
                DynamicIslandExpandedRegion(.leading) {
                    ManeuverStrip(
                        maneuvers: Array(context.state.maneuvers.prefix(2)),
                        firstIndex: 0,
                        alignment: .leading
                    )
                }
                .contentMargins(.leading, DynamicIslandMetrics.sideMargin)
                .contentMargins(.vertical, DynamicIslandMetrics.stripVerticalMargin)

                DynamicIslandExpandedRegion(.trailing) {
                    ManeuverStrip(
                        maneuvers: Array(context.state.maneuvers.dropFirst(2).prefix(2)),
                        firstIndex: 2,
                        alignment: .trailing
                    )
                }
                .contentMargins(.trailing, DynamicIslandMetrics.sideMargin)
                .contentMargins(.vertical, DynamicIslandMetrics.stripVerticalMargin)

                DynamicIslandExpandedRegion(.bottom) {
                    NavigationSummary(state: context.state)
                }
                .contentMargins(.horizontal, DynamicIslandMetrics.bottomSideMargin)
            } compactLeading: {
                Image(systemName: context.state.leadingManeuver.symbolName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TossWidgetColor.blue)
                    .padding(.leading, 2)
            } compactTrailing: {
                Text(context.state.headlineDistanceText)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 40)
                    .padding(.trailing, 2)
            } minimal: {
                Image(systemName: context.state.leadingManeuver.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TossWidgetColor.blue)
            }
            .keylineTint(TossWidgetColor.blue)
        }
    }
}

// MARK: - 여백과 크기

/// 다이나믹 아일랜드의 둥근 모서리를 피하기 위한 값들.
private enum DynamicIslandMetrics {
    /// 좌우 확장 영역이 바깥 모서리에서 떨어질 거리.
    static let sideMargin: Double = 22
    /// 동작 아이콘 줄이 위쪽 모서리에 닿지 않도록 하는 여백.
    static let stripVerticalMargin: Double = 8

    /// 아래 영역 좌우 여백.
    static let bottomSideMargin: Double = 14
    /// 마지막 줄과 아일랜드 바닥 사이 거리.
    /// 아래 두 모서리는 곡률이 커서, 이만큼 띄워야 글자가 곡선에 물리지 않습니다.
    static let bottomBreathingRoom: CGFloat = 22
    /// 좌우 모서리 곡선에서 가장 가까운 마지막 줄에만 추가로 주는 안쪽 여백.
    static let lastLineSideInset: CGFloat = 10

    /// 아래 영역이 최소한 확보하는 높이.
    /// 이 값이 곧 아일랜드의 세로 길이를 결정합니다. 잘리는 것보다 큰 편이 낫습니다.
    static let bottomMinHeight: CGFloat = 116

    static let maneuverSize: CGFloat = 19
    static let maneuverSpacing: CGFloat = 16
}

// MARK: - 상태 도우미

private extension FastMapActivityAttributes.ContentState {
    /// 지금 해야 할 동작. 아직 경로가 없으면 걷기 아이콘으로 둡니다.
    var leadingManeuver: WalkingManeuver {
        maneuvers.first ?? .crosswalk
    }

    /// 가장 크게 보여 줄 거리. 길안내 중이면 다음 동작까지의 거리입니다.
    var headlineDistanceText: String {
        maneuverDistanceText ?? distanceText
    }

    /// 목적지 아래 한 줄에 들어갈 보조 정보.
    var supportingText: String {
        guard let remainingTimeText else { return distanceText }
        return "\(remainingTimeText) · \(distanceText)"
    }
}

// MARK: - 동작 아이콘 줄

private struct ManeuverStrip: View {
    let maneuvers: [WalkingManeuver]
    /// 전체 목록에서 몇 번째부터인지. 0번만 또렷하게 그립니다.
    let firstIndex: Int
    let alignment: Alignment

    var body: some View {
        HStack(spacing: DynamicIslandMetrics.maneuverSpacing) {
            ForEach(Array(maneuvers.enumerated()), id: \.offset) { offset, maneuver in
                Image(systemName: maneuver.symbolName)
                    .font(.system(size: DynamicIslandMetrics.maneuverSize, weight: .bold))
                    .foregroundStyle(firstIndex + offset == 0 ? Color.white : Color.white.opacity(0.38))
                    .accessibilityLabel(maneuver.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.vertical, 4)
    }
}

// MARK: - 확장 영역 본문

private struct NavigationSummary: View {
    let state: FastMapActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(state.headlineDistanceText)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: state.leadingManeuver.symbolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(TossWidgetColor.blue)
                    .frame(width: 22, height: 22)
                    .background(
                        TossWidgetColor.blue.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                // 안내 문구가 길면 글자를 뭉개는 대신 두 줄로 늘립니다.
                Text(state.instructionText ?? state.directionText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 마지막 줄이 아래 모서리 곡선에 가장 가깝습니다.
            // 좌우로 한 번 더 들여쓰고, 아래에 여유 공간을 둬서 곡선에서 떼어 놓습니다.
            HStack(spacing: 6) {
                Text(state.placeName)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text(state.supportingText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, DynamicIslandMetrics.lastLineSideInset)
        }
        // 아일랜드 바닥과 마지막 줄 사이를 벌립니다. 아일랜드가 그만큼 세로로 커집니다.
        .padding(.bottom, DynamicIslandMetrics.bottomBreathingRoom)
        .frame(
            maxWidth: .infinity,
            minHeight: DynamicIslandMetrics.bottomMinHeight,
            alignment: .topLeading
        )
    }
}

// MARK: - 잠금화면

private struct LockScreenActivityView: View {
    let state: FastMapActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.maneuvers.isEmpty {
                HStack(spacing: 18) {
                    ForEach(Array(state.maneuvers.prefix(4).enumerated()), id: \.offset) { offset, maneuver in
                        Image(systemName: maneuver.symbolName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(offset == 0 ? Color.primary : Color.primary.opacity(0.32))
                            .accessibilityLabel(maneuver.title)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(state.headlineDistanceText)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)

                Text(state.instructionText ?? state.directionText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                    .font(.caption2.weight(.bold))
                Text(state.placeName)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(state.supportingText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

/// Live Activity 타깃 전용 토스 블루 (앱 타깃의 TossColor와 동일한 값).
enum TossWidgetColor {
    static let blue = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x4B / 255, green: 0x93 / 255, blue: 0xF8 / 255, alpha: 1)
                : UIColor(red: 0x31 / 255, green: 0x82 / 255, blue: 0xF6 / 255, alpha: 1)
        }
    )
}
