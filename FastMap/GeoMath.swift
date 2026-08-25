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

    /// 기준점에서 방위·거리만큼 떨어진 좌표.
    ///
    /// 넓은 지역을 한 번의 호출로 다 담을 수 없어서 여러 지점으로 나눠 훑을 때,
    /// 그 지점들을 만드는 데 씁니다.
    static func coordinate(
        from origin: CLLocationCoordinate2D,
        distanceMeters: CLLocationDistance,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distanceMeters / earthRadius
        let bearing = bearingDegrees.toRadians
        let lat1 = origin.latitude.toRadians
        let lon1 = origin.longitude.toRadians

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2.toDegrees, longitude: lon2.toDegrees)
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
