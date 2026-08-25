import Combine
import CoreLocation
import CoreMotion
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private var latestMotionHeading: Double?
    private var motionHeadingOffset: Double?
    private var hasValidCompassHeading = false

    @Published var currentLocation: CLLocationCoordinate2D = .seoulCityHall
    @Published var headingDegrees: Double = 0
    /// 길안내 중 지도 회전에 쓰는 방향입니다. Core Motion이 자이로·가속도계·나침반을
    /// 결합해 주기 때문에 CLLocationManager의 나침반 값보다 손의 회전에 빠르게 반응합니다.
    @Published var navigationHeadingDegrees: Double = 0
    @Published var horizontalAccuracy: CLLocationAccuracy = .greatestFiniteMagnitude
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
        stopNavigationMotionUpdates()
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

    /// 50m 단위 거리 필터를 켰을 때 쓰는 정밀 위치 갱신입니다.
    func startProximityUpdates() {
        stopNavigationMotionUpdates()
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .other
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func startNavigationUpdates(for mode: NavigationMode) {
        guard manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = switch mode {
        case .walking, .bicycle: .fitness
        case .automobile: .automotiveNavigation
        case .transit: .otherNavigation
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 3
            manager.startUpdatingHeading()
        }
        startNavigationMotionUpdates()
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        stopNavigationMotionUpdates()
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
            horizontalAccuracy = location.horizontalAccuracy
            isUsingFallbackLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            headingDegrees = heading
            hasValidCompassHeading = true

            if let latestMotionHeading {
                motionHeadingOffset = Self.signedAngle(from: latestMotionHeading, to: heading)
            }
            navigationHeadingDegrees = heading
        }
    }

    private func startNavigationMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else {
            navigationHeadingDegrees = headingDegrees
            return
        }

        latestMotionHeading = nil
        motionHeadingOffset = nil
        navigationHeadingDegrees = headingDegrees
        motionManager.deviceMotionUpdateInterval = 1.0 / 15.0
        motionManager.showsDeviceMovementDisplay = true
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let motion, motion.heading >= 0 else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                latestMotionHeading = motion.heading

                if motionHeadingOffset == nil, hasValidCompassHeading {
                    motionHeadingOffset = Self.signedAngle(from: motion.heading, to: headingDegrees)
                }

                let corrected = Self.normalizedHeading(motion.heading + (motionHeadingOffset ?? 0))
                guard Self.angularDistance(corrected, navigationHeadingDegrees) >= 0.5 else { return }
                navigationHeadingDegrees = corrected
            }
        }
    }

    private func stopNavigationMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
        latestMotionHeading = nil
        motionHeadingOffset = nil
        navigationHeadingDegrees = headingDegrees
    }

    private static func normalizedHeading(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    private static func signedAngle(from start: Double, to end: Double) -> Double {
        let difference = normalizedHeading(end) - normalizedHeading(start)
        return (difference + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        abs(signedAngle(from: first, to: second))
    }

    static var preview: LocationService {
        let service = LocationService()
        service.currentLocation = .seoulCityHall
        return service
    }
}
