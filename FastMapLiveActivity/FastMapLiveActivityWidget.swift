import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct FastMapLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastMapActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(TossWidgetColor.background)
                .activitySystemActionForegroundColor(TossWidgetColor.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandMetric(
                        systemName: "clock.fill",
                        text: context.state.displayRemainingTimeText,
                        alignment: .leading
                    )
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    IslandMetric(
                        systemName: "location.fill",
                        text: context.state.distanceText,
                        alignment: .trailing
                    )
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    NavigationSummary(state: context.state)
                }
            } compactLeading: {
                Text(context.state.compactRemainingTimeText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TossWidgetColor.blue)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 43, alignment: .leading)
            } compactTrailing: {
                Text(context.state.distanceText)
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

/// 확장형 다이나믹 아일랜드를 160pt 안쪽에 유지하기 위한 값들.
private enum DynamicIslandMetrics {
    /// 마지막 줄과 아일랜드 바닥 사이 거리.
    /// 시스템 기본 content margin에 더하는 작은 여백만 사용합니다.
    static let bottomBreathingRoom: CGFloat = 8
    /// 좌우 모서리 곡선에서 가장 가까운 마지막 줄에만 추가로 주는 안쪽 여백.
    static let lastLineSideInset: CGFloat = 4
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

    var displayRemainingTimeText: String {
        remainingTimeText ?? "계산 중"
    }

    var compactRemainingTimeText: String {
        displayRemainingTimeText.replacingOccurrences(of: "약 ", with: "")
    }
}

// MARK: - 확장 영역 지표

private struct IslandMetric: View {
    let systemName: String
    let text: String
    let alignment: Alignment

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TossWidgetColor.blue)
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

// MARK: - 확장 영역 본문

private struct NavigationSummary: View {
    let state: FastMapActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(state.headlineDistanceText)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 4)

                HStack(spacing: 10) {
                    ForEach(Array(state.maneuvers.prefix(4).enumerated()), id: \.offset) { offset, maneuver in
                        Image(systemName: maneuver.symbolName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(offset == 0 ? TossWidgetColor.blue : Color.white.opacity(0.35))
                            .accessibilityLabel(maneuver.title)
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: state.leadingManeuver.symbolName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TossWidgetColor.blue)
                    .frame(width: 20, height: 20)
                    .background(
                        TossWidgetColor.blue.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                // 확장형 전체 높이를 넘기지 않도록 한 줄에서 자연스럽게 축소합니다.
                Text(state.instructionText ?? state.directionText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
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
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, DynamicIslandMetrics.lastLineSideInset)
        }
        // 시스템의 기본 안전 여백을 유지한 채 바닥에 최소한의 호흡만 더합니다.
        .padding(.bottom, DynamicIslandMetrics.bottomBreathingRoom)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

/// Live Activity 타깃 전용 일렉트릭 블루 (앱 타깃의 TossColor와 동일한 값).
enum TossWidgetColor {
    static let blue = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x58 / 255, green: 0xC7 / 255, blue: 0xFF / 255, alpha: 1)
                : UIColor(red: 0x24 / 255, green: 0x68 / 255, blue: 0xE8 / 255, alpha: 1)
        }
    )

    static let background = Color(
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x07 / 255, green: 0x0A / 255, blue: 0x0E / 255, alpha: 1)
                : UIColor(red: 0xF3 / 255, green: 0xF7 / 255, blue: 0xFF / 255, alpha: 1)
        }
    )
}
