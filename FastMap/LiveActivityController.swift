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

    func startTracking(place: Place, deviceHeadingDegrees: Double) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusText = "기기에서 Live Activity가 꺼져 있습니다."
            return
        }

        let contentState = contentState(for: place, deviceHeadingDegrees: deviceHeadingDegrees)
        let attributes = FastMapActivityAttributes(
            destinationName: place.name,
            categoryTitle: place.category.title
        )

        do {
            if let activity {
                await activity.update(ActivityContent(state: contentState, staleDate: Date().addingTimeInterval(10 * 60)))
            } else {
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: contentState, staleDate: Date().addingTimeInterval(10 * 60)),
                    pushType: nil
                )
            }

            isRunning = true
            statusText = "잠금화면과 Dynamic Island에서 표시 중"
        } catch {
            statusText = "Live Activity를 시작하지 못했습니다."
        }
    }

    func update(place: Place?, deviceHeadingDegrees: Double) async {
        guard let activity, let place else { return }
        await activity.update(
            ActivityContent(
                state: contentState(for: place, deviceHeadingDegrees: deviceHeadingDegrees),
                staleDate: Date().addingTimeInterval(10 * 60)
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

    private func contentState(for place: Place, deviceHeadingDegrees: Double) -> FastMapActivityAttributes.ContentState {
        FastMapActivityAttributes.ContentState(
            placeName: place.name,
            categoryTitle: place.category.title,
            distanceText: GeoMath.formattedDistance(place.distanceMeters),
            directionText: GeoMath.directionText(for: place.bearingDegrees),
            arrowRotationDegrees: relativeArrowRotation(destinationBearing: place.bearingDegrees, deviceHeading: deviceHeadingDegrees),
            updatedAt: Date()
        )
    }

    private func relativeArrowRotation(destinationBearing: Double, deviceHeading: Double) -> Double {
        let normalized = (destinationBearing - deviceHeading + 360).truncatingRemainder(dividingBy: 360)
        return normalized > 180 ? normalized - 360 : normalized
    }
}
