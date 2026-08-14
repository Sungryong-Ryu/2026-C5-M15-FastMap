import CoreLocation
import Foundation

enum GeoMath {
    static func distanceMeters(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))
    }

    static func bearingDegrees(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = origin.latitude.toRadians
        let lat2 = destination.latitude.toRadians
        let deltaLongitude = (destination.longitude - origin.longitude).toRadians
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        return (atan2(y, x).toDegrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func directionText(for bearing: Double) -> String {
        let directions = ["북쪽", "북동쪽", "동쪽", "남동쪽", "남쪽", "남서쪽", "서쪽", "북서쪽"]
        let index = Int((bearing + 22.5) / 45.0) % directions.count
        return directions[index]
    }

    static func formattedDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters.rounded())) m"
    }
}

private extension Double {
    var toRadians: Double { self * .pi / 180 }
    var toDegrees: Double { self * 180 / .pi }
}
