import ActivityKit
import Combine
import Foundation

@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "라이브 활동 대기 중"

    private var activity: Activity<FastMapActivityAttributes>?

    init() {
        activity = Activity<FastMapActivityAttributes>.activities.first
        isRunning = activity != nil
        statusText = isRunning ? "잠금화면과 Dynamic Island에서 표시 중" : "라이브 활동 대기 중"
    }

    func startTracking(cafe: Cafe, deviceHeadingDegrees: Double) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusText = "기기에서 Live Activity가 꺼져 있습니다."
            return
        }

        let contentState = contentState(for: cafe, deviceHeadingDegrees: deviceHeadingDegrees)
        let attributes = FastMapActivityAttributes(
            destinationName: cafe.name,
            categoryTitle: cafe.tagline
        )

        // ActivityKit의 attributes는 시작한 뒤 바꿀 수 없습니다.
        // 앱을 강제 종료했다가 다시 켜면 init에서 살아 있던 활동을 그대로 물려받는데,
        // 그 상태로 다른 카페 길안내를 시작하면 잠금화면에는 예전 목적지 이름이 남습니다.
        // 목적지가 달라졌으면 기존 활동을 끝내고 새로 요청합니다.
        if let existing = activity, existing.attributes.destinationName != cafe.name {
            await existing.end(nil, dismissalPolicy: .immediate)
            activity = nil
        }

        do {
            if let activity {
                await activity.update(
                    ActivityContent(
                        state: contentState,
                        staleDate: Date().addingTimeInterval(10 * 60),
                        relevanceScore: 100
                    )
                )
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(
                        state: contentState,
                        staleDate: Date().addingTimeInterval(10 * 60),
                        relevanceScore: 100
                    ),
                    pushType: nil
                )
            }

            isRunning = true
            statusText = "잠금화면과 Dynamic Island에서 표시 중"
        } catch {
            statusText = "Live Activity를 시작하지 못했습니다."
        }
    }

    func update(cafe: Cafe?, deviceHeadingDegrees: Double) async {
        guard let activity, let cafe else { return }
        await activity.update(
            ActivityContent(
                state: contentState(for: cafe, deviceHeadingDegrees: deviceHeadingDegrees),
                staleDate: Date().addingTimeInterval(10 * 60),
                relevanceScore: 100
            )
        )
    }

    func updateNavigation(cafe: Cafe, snapshot: WalkingNavigationSnapshot) async {
        guard let activity else { return }
        let state = FastMapActivityAttributes.ContentState(
            placeName: cafe.name,
            categoryTitle: cafe.tagline,
            distanceText: snapshot.distanceText,
            directionText: "\(snapshot.modeTitle) 길안내",
            arrowRotationDegrees: snapshot.arrowRotationDegrees,
            updatedAt: Date(),
            instructionText: snapshot.instruction,
            remainingTimeText: snapshot.remainingTimeText,
            maneuvers: snapshot.maneuvers,
            maneuverDistanceText: snapshot.maneuverDistanceText
        )
        await activity.update(
            ActivityContent(
                state: state,
                staleDate: Date().addingTimeInterval(5 * 60),
                relevanceScore: 100
            )
        )
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        isRunning = false
        statusText = "라이브 활동 대기 중"
    }

    private func contentState(for cafe: Cafe, deviceHeadingDegrees: Double) -> FastMapActivityAttributes.ContentState {
        FastMapActivityAttributes.ContentState(
            placeName: cafe.name,
            categoryTitle: cafe.tagline,
            distanceText: GeoMath.formattedDistance(cafe.distanceMeters),
            directionText: GeoMath.directionText(for: cafe.bearingDegrees),
            arrowRotationDegrees: relativeArrowRotation(destinationBearing: cafe.bearingDegrees, deviceHeading: deviceHeadingDegrees),
            updatedAt: Date()
        )
    }

    private func relativeArrowRotation(destinationBearing: Double, deviceHeading: Double) -> Double {
        let normalized = (destinationBearing - deviceHeading + 360).truncatingRemainder(dividingBy: 360)
        return normalized > 180 ? normalized - 360 : normalized
    }
}
