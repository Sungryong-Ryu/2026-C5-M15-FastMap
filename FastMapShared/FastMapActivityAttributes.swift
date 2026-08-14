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
    }

    var destinationName: String
    var categoryTitle: String
}
