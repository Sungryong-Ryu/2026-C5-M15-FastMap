import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocationCoordinate2D = .seoulCityHall
    @Published var headingDegrees: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUsingFallbackLocation = true

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 80
        authorizationStatus = manager.authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            startEfficientUpdates()
        case .denied, .restricted:
            isUsingFallbackLocation = true
        @unknown default:
            isUsingFallbackLocation = true
        }
    }

    func startEfficientUpdates() {
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 80
        manager.activityType = .other
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func startNavigationUpdates() {
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 3
            manager.startUpdatingHeading()
        }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
                startEfficientUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location.coordinate
            isUsingFallbackLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    static var preview: LocationService {
        let service = LocationService()
        service.currentLocation = .seoulCityHall
        return service
    }
}
