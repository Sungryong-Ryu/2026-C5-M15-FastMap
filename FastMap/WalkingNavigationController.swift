import AVFoundation
import Combine
import CoreLocation
import MapKit

struct WalkingNavigationSnapshot: Equatable {
    let instruction: String
    let distanceText: String
    let remainingTimeText: String
    let modeTitle: String
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
            modeTitle: modeTitle,
            arrowRotationDegrees: degrees,
            maneuvers: maneuvers,
            maneuverDistanceText: maneuverDistanceText
        )
    }
}

@MainActor
final class WalkingNavigationController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var destination: Cafe?
    @Published private(set) var route: NavigationRoute?
    @Published private(set) var steps: [NavigationRouteStep] = []
    @Published private(set) var mode: NavigationMode = .walking
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var currentInstruction = "경로를 준비하고 있습니다"
    @Published private(set) var distanceToManeuver = 0.0
    @Published private(set) var remainingDistance = 0.0
    @Published private(set) var remainingTravelTime: TimeInterval = 0
    @Published private(set) var isNavigating = false
    @Published private(set) var isRerouting = false
    @Published private(set) var errorMessage: String?

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let routingService = KakaoRoutingService()
    private var lastSpokenStepIndex = -1
    private var offRouteUpdateCount = 0
    private var lastRerouteAt = Date.distantPast
    private var hasAnnouncedArrival = false

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    var snapshot: WalkingNavigationSnapshot? {
        guard isNavigating else { return nil }
        return WalkingNavigationSnapshot(
            instruction: currentInstruction,
            distanceText: GeoMath.formattedDistance(remainingDistance),
            remainingTimeText: Self.formattedTime(remainingTravelTime),
            modeTitle: mode.title,
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
            .map { WalkingManeuver.infer(from: $0.instruction) }
    }

    func start(
        to destination: Cafe,
        from origin: CLLocationCoordinate2D,
        mode: NavigationMode
    ) async {
        self.destination = destination
        self.mode = mode
        route = nil
        steps = []
        isNavigating = false
        errorMessage = nil
        isRerouting = true
        currentInstruction = "\(mode.title) 경로를 찾고 있습니다"
        lastRerouteAt = .distantPast
        defer { isRerouting = false }

        do {
            let newRoute = try await calculateRoute(mode: mode, from: origin, to: destination)
            install(newRoute, from: origin, announce: true)
        } catch {
            errorMessage = routeErrorMessage(mode: mode, error: error)
            isNavigating = false
        }
    }

    func changeMode(to newMode: NavigationMode, from origin: CLLocationCoordinate2D) async {
        guard let destination, newMode != mode, !isRerouting else { return }
        let previousInstruction = currentInstruction
        errorMessage = nil
        isRerouting = true
        currentInstruction = "\(newMode.title) 경로를 찾고 있습니다"
        defer { isRerouting = false }

        do {
            let newRoute = try await calculateRoute(mode: newMode, from: origin, to: destination)
            mode = newMode
            install(newRoute, from: origin, announce: true)
        } catch {
            currentInstruction = previousInstruction
            errorMessage = routeErrorMessage(mode: newMode, error: error)
        }
    }

    func updateLocation(
        _ coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: CLLocationAccuracy
    ) async {
        guard isNavigating, let route, let destination else { return }

        if GeoMath.distanceMeters(from: coordinate, to: destination.coordinate) < mode.arrivalDistance {
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
        let usableAccuracy = horizontalAccuracy >= 0 ? min(horizontalAccuracy, 50) : 0
        let offRouteThreshold = max(mode.offRouteDistance, usableAccuracy * 1.35)
        if offRouteDistance > offRouteThreshold {
            offRouteUpdateCount += 1
        } else {
            offRouteUpdateCount = 0
        }

        let isClearlyOffRoute = offRouteDistance > offRouteThreshold * 1.8
        if (offRouteUpdateCount >= 2 || isClearlyOffRoute),
           Date().timeIntervalSince(lastRerouteAt) > 8,
           !isRerouting {
            let previousInstruction = currentInstruction
            lastRerouteAt = Date()
            offRouteUpdateCount = 0
            isRerouting = true
            currentInstruction = "경로 이탈 · 새 경로를 찾는 중"
            do {
                let newRoute = try await calculateRoute(mode: mode, from: coordinate, to: destination)
                install(newRoute, from: coordinate, announce: true)
            } catch {
                currentInstruction = previousInstruction
                errorMessage = "경로를 다시 찾지 못했습니다."
            }
            isRerouting = false
        }
    }

    func stop() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        deactivateSpeechAudioSession()
        destination = nil
        route = nil
        steps = []
        mode = .walking
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
        lastRerouteAt = .distantPast
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
        return steps[currentStepIndex].targetCoordinate
    }

    private func install(_ route: NavigationRoute, from origin: CLLocationCoordinate2D, announce: Bool) {
        self.route = route
        steps = route.steps
        currentStepIndex = 0
        isNavigating = true
        errorMessage = nil
        lastSpokenStepIndex = -1
        offRouteUpdateCount = 0
        hasAnnouncedArrival = false
        updateProgress(from: origin)
        announceCurrentStepIfNeeded(force: announce)
    }

    private func advanceStepIfNeeded(from coordinate: CLLocationCoordinate2D) {
        while steps.indices.contains(currentStepIndex) {
            let target = steps[currentStepIndex].targetCoordinate
            let distance = GeoMath.distanceMeters(from: coordinate, to: target)
            let baseThreshold: CLLocationDistance = mode == .automobile ? 35 : 14
            let maxThreshold: CLLocationDistance = mode == .automobile ? 80 : 35
            let threshold = min(maxThreshold, max(baseThreshold, steps[currentStepIndex].distance * 0.16))
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
            let instruction = steps[currentStepIndex].instruction
            currentInstruction = instruction.isEmpty ? "경로를 따라 이동하세요" : instruction
        }
    }

    private func announceCurrentStepIfNeeded(force: Bool) {
        guard force || lastSpokenStepIndex != currentStepIndex else { return }
        lastSpokenStepIndex = currentStepIndex
        speak(currentInstruction)
    }

    private func calculateRoute(
        mode: NavigationMode,
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        if let routingService {
            do {
                return try await routingService.route(mode: mode, from: origin, to: destination)
            } catch {
                // 자전거는 MapKit에 대응하는 경로 유형이 없어 Kakao 오류를 그대로 보여 줍니다.
                if mode == .bicycle { throw error }
            }
        } else if mode == .bicycle {
            throw KakaoRoutingError.missingAPIKey
        }

        return try await mapKitFallbackRoute(mode: mode, from: origin, to: destination)
    }

    private func mapKitFallbackRoute(
        mode: NavigationMode,
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil
        )
        request.destination = destination.mapItem
        request.transportType = switch mode {
        case .walking: .walking
        case .automobile: .automobile
        case .transit: .transit
        case .bicycle: .walking
        }
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw NavigationError.noRoute }

        let convertedSteps = route.steps.compactMap { step -> NavigationRouteStep? in
            guard !step.instructions.isEmpty || step.distance > 0,
                  let target = step.polyline.navigationCoordinates.last else { return nil }
            return NavigationRouteStep(
                instruction: step.instructions.isEmpty ? "경로를 따라 이동하세요" : step.instructions,
                distance: step.distance,
                targetCoordinate: target,
                systemImage: mode.systemImage
            )
        }
        return NavigationRoute(
            polyline: route.polyline,
            steps: convertedSteps,
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            landingURL: nil,
            provider: .appleMapKit,
            detailText: "Kakao 연결이 불안정해 Apple 경로를 사용 중"
        )
    }

    private func routeErrorMessage(mode: NavigationMode, error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return "\(mode.title) 경로를 불러오지 못했습니다."
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        speechSynthesizer.stopSpeaking(at: .immediate)
        activateSpeechAudioSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = 0.47
        speechSynthesizer.speak(utterance)
    }

    /// 안내 음성이 나오는 동안에만 음악을 작게 만들고, 끝나면 원래 볼륨으로 돌립니다.
    private func activateSpeechAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
        } catch {
            // 음성 안내가 실패해도 경로 자체는 계속 동작해야 합니다.
        }
    }

    private func deactivateSpeechAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if !self.speechSynthesizer.isSpeaking { self.deactivateSpeechAudioSession() }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if !self.speechSynthesizer.isSpeaking { self.deactivateSpeechAudioSession() }
        }
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
