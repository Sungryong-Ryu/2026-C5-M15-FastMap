import ActivityKit
import Foundation

struct FastMapActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var placeName: String
        var categoryTitle: String
        var distanceText: String
        var directionText: String
        var arrowRotationDegrees: Double
        var updatedAt: Date
        var instructionText: String? = nil
        var remainingTimeText: String? = nil
        /// 앞으로 다가올 동작들. Dynamic Island 위쪽 줄에 순서대로 그립니다.
        var maneuvers: [WalkingManeuver] = []
        /// 다음 동작까지 남은 거리. 화면에서 가장 크게 보여 주는 값입니다.
        var maneuverDistanceText: String? = nil
    }

    var destinationName: String
    var categoryTitle: String
}
