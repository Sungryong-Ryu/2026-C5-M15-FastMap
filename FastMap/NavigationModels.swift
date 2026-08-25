import CoreLocation
import Foundation
import MapKit

enum NavigationMode: String, CaseIterable, Identifiable {
    case walking
    case automobile
    case bicycle
    case transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .walking: "도보"
        case .automobile: "자동차"
        case .bicycle: "자전거"
        case .transit: "대중교통"
        }
    }

    var systemImage: String {
        switch self {
        case .walking: "figure.walk"
        case .automobile: "car.fill"
        case .bicycle: "bicycle"
        case .transit: "bus.fill"
        }
    }

    var arrivalDistance: CLLocationDistance {
        switch self {
        case .walking: 18
        case .bicycle: 25
        case .automobile: 40
        case .transit: 45
        }
    }

    var offRouteDistance: CLLocationDistance {
        switch self {
        case .walking: 45
        case .bicycle: 60
        case .automobile: 90
        case .transit: 100
        }
    }
}

struct NavigationRouteStep: Identifiable {
    let id = UUID()
    let instruction: String
    let distance: CLLocationDistance
    let targetCoordinate: CLLocationCoordinate2D
    let systemImage: String?
}

struct NavigationRoute {
    enum Provider {
        case kakaoMap
        case kakaoMobility
        case appleMapKit

        var title: String {
            switch self {
            case .kakaoMap: "카카오맵"
            case .kakaoMobility: "카카오모빌리티"
            case .appleMapKit: "Apple 지도"
            }
        }
    }

    let polyline: MKPolyline
    let steps: [NavigationRouteStep]
    let distance: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let landingURL: URL?
    let provider: Provider
    let detailText: String?
}

extension MKPolyline {
    var navigationCoordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}
