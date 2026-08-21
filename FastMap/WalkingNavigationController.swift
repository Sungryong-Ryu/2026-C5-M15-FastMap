import AVFoundation
import Combine
import CoreLocation
import MapKit

struct WalkingNavigationSnapshot: Equatable {
    let instruction: String
    let distanceText: String
    let remainingTimeText: String
    let arrowRotationDegrees: Double
    /// 앞으로 다가올 동작들 (최대 4개).
    let maneuvers: [WalkingManeuver]
    /// 다음 동작까지 남은 거리.
    let maneuverDistanceText: String

    /// 기기 방향에 맞춘 화살표 각도만 바꿔서 복사합니다.
    func withArrowRotation(_ degrees: Double) -> WalkingNavigationSnapshot {
        WalkingNavigationSnapshot(
            instruction: instruction,
            distanceText: distanceText,
            remainingTimeText: remainingTimeText,
            arrowRotationDegrees: degrees,
            maneuvers: maneuvers,
            maneuverDistanceText: maneuverDistanceText
        )
    }
}

@MainActor
final class WalkingNavigationController: ObservableObject {
    @Published private(set) var destination: Place?
    @Published private(set) var route: MKRoute?
    @Published private(set) var steps: [MKRoute.Step] = []
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var currentInstruction = "경로를 준비하고 있습니다"
    @Published private(set) var distanceToManeuver = 0.0
    @Published private(set) var remainingDistance = 0.0
    @Published private(set) var remainingTravelTime: TimeInterval = 0
    @Published private(set) var isNavigating = false
    @Published private(set) var isRerouting = false
    @Published private(set) var errorMessage: String?

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenStepIndex = -1
    private var offRouteUpdateCount = 0
    private var lastRerouteAt = Date.distantPast
    private var hasAnnouncedArrival = false

    var snapshot: WalkingNavigationSnapshot? {
        guard isNavigating else { return nil }
        return WalkingNavigationSnapshot(
            instruction: currentInstruction,
            distanceText: GeoMath.formattedDistance(remainingDistance),
            remainingTimeText: Self.formattedTime(remainingTravelTime),
            arrowRotationDegrees: 0,
            maneuvers: upcomingManeuvers,
            maneuverDistanceText: GeoMath.formattedDistance(distanceToManeuver)
        )
    }

    /// 지금 동작부터 앞으로 다가올 동작 최대 4개.
    var upcomingManeuvers: [WalkingManeuver] {
        guard steps.indices.contains(currentStepIndex) else { return [] }
        return steps[currentStepIndex...]
            .prefix(4)
            .map { WalkingManeuver.infer(from: $0.instructions) }
    }

    func start(to destination: Place, from origin: CLLocationCoordinate2D, route preferredRoute: MKRoute? = nil) async {
        self.destination = destination
        errorMessage = nil
        isRerouting = true
        defer { isRerouting = false }

        if let preferredRoute {
            install(preferredRoute, from: origin, announce: true)
            return
        }

        do {
            let route = try await calculateRoute(from: origin, to: destination)
            install(route, from: origin, announce: true)
        } catch {
            errorMessage = "도보 경로를 불러오지 못했습니다."
            isNavigating = false
        }
    }

    func updateLocation(_ coordinate: CLLocationCoordinate2D, headingDegrees: Double) async {
        guard isNavigating, let route, let destination else { return }

        if GeoMath.distanceMeters(from: coordinate, to: destination.coordinate) < 18 {
            currentInstruction = "목적지에 도착했습니다"
            distanceToManeuver = 0
            remainingDistance = 0
            remainingTravelTime = 0
            if !hasAnnouncedArrival {
                hasAnnouncedArrival = true
                speak("목적지에 도착했습니다")
            }
            return
        }

        advanceStepIfNeeded(from: coordinate)
        updateProgress(from: coordinate)

        let offRouteDistance = distanceFromRoute(coordinate, polyline: route.polyline)
        if offRouteDistance > 45 {
            offRouteUpdateCount += 1
        } else {
            offRouteUpdateCount = 0
        }

        if offRouteUpdateCount >= 3,
           Date().timeIntervalSince(lastRerouteAt) > 15,
           !isRerouting {
            lastRerouteAt = Date()
            offRouteUpdateCount = 0
            isRerouting = true
            currentInstruction = "경로를 다시 찾고 있습니다"
            do {
                let newRoute = try await calculateRoute(from: coordinate, to: destination)
                install(newRoute, from: coordinate, announce: true)
            } catch {
                errorMessage = "경로를 다시 찾지 못했습니다."
            }
            isRerouting = false
        }

    }

    func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        destination = nil
        route = nil
        steps = []
        currentStepIndex = 0
        currentInstruction = "경로를 준비하고 있습니다"
        distanceToManeuver = 0
        remainingDistance = 0
        remainingTravelTime = 0
        isNavigating = false
        isRerouting = false
        errorMessage = nil
        lastSpokenStepIndex = -1
        offRouteUpdateCount = 0
        hasAnnouncedArrival = false
    }

    func arrowRotation(deviceHeadingDegrees: Double, from origin: CLLocationCoordinate2D) -> Double {
        guard let target = currentStepTarget ?? destination?.coordinate else { return 0 }
        let bearing = GeoMath.bearingDegrees(from: origin, to: target)
        let normalized = (bearing - deviceHeadingDegrees + 360).truncatingRemainder(dividingBy: 360)
        return normalized > 180 ? normalized - 360 : normalized
    }

    private var currentStepTarget: CLLocationCoordinate2D? {
        guard steps.indices.contains(currentStepIndex) else { return destination?.coordinate }
        return steps[currentStepIndex].polyline.coordinates.last
    }

    private func install(_ route: MKRoute, from origin: CLLocationCoordinate2D, announce: Bool) {
        self.route = route
        steps = route.steps.filter { !$0.instructions.isEmpty || $0.distance > 0 }
        currentStepIndex = 0
        isNavigating = true
        lastSpokenStepIndex = -1
        hasAnnouncedArrival = false
        updateProgress(from: origin)
        announceCurrentStepIfNeeded(force: announce)
    }

    private func advanceStepIfNeeded(from coordinate: CLLocationCoordinate2D) {
        while steps.indices.contains(currentStepIndex) {
            guard let target = steps[currentStepIndex].polyline.coordinates.last else { break }
            let distance = GeoMath.distanceMeters(from: coordinate, to: target)
            let threshold = min(35, max(14, steps[currentStepIndex].distance * 0.16))
            guard distance <= threshold, currentStepIndex < steps.count - 1 else { break }
            currentStepIndex += 1
            announceCurrentStepIfNeeded(force: false)
        }
    }

    private func updateProgress(from coordinate: CLLocationCoordinate2D) {
        guard let route else { return }
        let target = currentStepTarget ?? destination?.coordinate ?? coordinate
        distanceToManeuver = GeoMath.distanceMeters(from: coordinate, to: target)

        let laterDistance = steps.indices.contains(currentStepIndex)
            ? steps.dropFirst(currentStepIndex + 1).reduce(0) { $0 + $1.distance }
            : 0
        remainingDistance = min(route.distance, max(0, distanceToManeuver + laterDistance))
        let progressRatio = route.distance > 0 ? remainingDistance / route.distance : 0
        remainingTravelTime = route.expectedTravelTime * progressRatio

        if steps.indices.contains(currentStepIndex) {
            let instruction = steps[currentStepIndex].instructions
            currentInstruction = instruction.isEmpty ? "경로를 따라 이동하세요" : instruction
        }
    }

    private func announceCurrentStepIfNeeded(force: Bool) {
        guard force || lastSpokenStepIndex != currentStepIndex else { return }
        lastSpokenStepIndex = currentStepIndex
        speak(currentInstruction)
    }

    private func calculateRoute(from origin: CLLocationCoordinate2D, to destination: Place) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = destination.mapItem
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw NavigationError.noRoute }
        return route
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.47
        speechSynthesizer.speak(utterance)
    }

    private func distanceFromRoute(_ coordinate: CLLocationCoordinate2D, polyline: MKPolyline) -> Double {
        let points = polyline.points()
        guard polyline.pointCount > 1 else { return .infinity }
        let point = MKMapPoint(coordinate)
        var shortest = Double.greatestFiniteMagnitude

        for index in 0..<(polyline.pointCount - 1) {
            shortest = min(shortest, Self.distance(point, toSegmentFrom: points[index], to: points[index + 1]))
        }
        return shortest * MKMetersPerMapPointAtLatitude(coordinate.latitude)
    }

    private static func distance(_ point: MKMapPoint, toSegmentFrom start: MKMapPoint, to end: MKMapPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let clamped = min(1, max(0, projection))
        let nearestX = start.x + clamped * dx
        let nearestY = start.y + clamped * dy
        return hypot(point.x - nearestX, point.y - nearestY)
    }

    static func formattedTime(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(interval / 60)))
        return "약 \(minutes)분"
    }

    private enum NavigationError: Error {
        case noRoute
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coordinates = Array(repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
        return coordinates
    }
}
