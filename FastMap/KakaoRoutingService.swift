import CoreLocation
import Foundation
import MapKit

enum KakaoRoutingError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case quotaExceeded
    case noRoute
    case badResponse(Int)
    case malformedResponse
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Kakao REST API 키가 없습니다."
        case .unauthorized: "Kakao 길찾기 권한을 확인해 주세요."
        case .quotaExceeded: "오늘 Kakao 길찾기 호출 한도를 다 썼습니다."
        case .noRoute: "선택한 이동수단으로 갈 수 있는 경로가 없습니다."
        case .badResponse(let code): "Kakao 길찾기 응답 오류 (\(code))"
        case .malformedResponse: "Kakao 경로 데이터를 읽지 못했습니다."
        case .transport: "네트워크에 연결할 수 없습니다."
        }
    }
}

struct KakaoRoutingService {
    private let apiKey: String
    private let session: URLSession

    init?(apiKey: String? = AppSecrets.kakaoRESTAPIKey, session: URLSession = .shared) {
        guard let apiKey else { return nil }
        self.apiKey = apiKey
        self.session = session
    }

    func route(
        mode: NavigationMode,
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        switch mode {
        case .walking:
            try await activeRoute(path: "/v2/routing/walk", mode: mode, from: origin, to: destination)
        case .bicycle:
            try await activeRoute(path: "/v2/routing/bicycle", mode: mode, from: origin, to: destination)
        case .transit:
            try await transitRoute(from: origin, to: destination)
        case .automobile:
            try await automobileRoute(from: origin, to: destination)
        }
    }

    private func activeRoute(
        path: String,
        mode: NavigationMode,
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        let response: ActiveResponse = try await request(
            host: "dapi.kakao.com",
            path: path,
            queryItems: coordinateQuery(from: origin, to: destination)
        )
        guard response.status == "OK", let route = response.route else { throw KakaoRoutingError.noRoute }

        let rawSteps = route.legs.flatMap(\.steps)
        let allCoordinates = rawSteps.flatMap { coordinates(from: $0.path.points) }
        let steps = rawSteps.compactMap { step -> NavigationRouteStep? in
            let points = coordinates(from: step.path.points)
            guard let target = points.last else { return nil }
            return NavigationRouteStep(
                instruction: step.properties.guidance.isEmpty ? "경로를 따라 이동하세요" : step.properties.guidance,
                distance: CLLocationDistance(step.properties.distance),
                targetCoordinate: target,
                systemImage: mode.systemImage
            )
        }

        return NavigationRoute(
            polyline: try polyline(from: allCoordinates, origin: origin, destination: destination.coordinate),
            steps: steps,
            distance: CLLocationDistance(route.properties.totalDistance),
            expectedTravelTime: TimeInterval(route.properties.totalTime),
            landingURL: URL(string: route.properties.landingUrl),
            provider: .kakaoMap,
            detailText: nil
        )
    }

    private func transitRoute(
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        let response: TransitResponse = try await request(
            host: "dapi.kakao.com",
            path: "/v2/routing/publictraffic",
            queryItems: coordinateQuery(from: origin, to: destination)
        )
        guard response.status == "OK", let route = response.routes?.first else {
            throw KakaoRoutingError.noRoute
        }

        let allCoordinates = route.steps.flatMap { coordinates(from: $0.path.points) }
        var steps = route.steps.compactMap { step -> NavigationRouteStep? in
            let points = coordinates(from: step.path.points)
            guard let target = points.last else { return nil }
            return NavigationRouteStep(
                instruction: step.properties.guidance.isEmpty ? "대중교통 경로를 따라 이동하세요" : step.properties.guidance,
                distance: CLLocationDistance(step.properties.distance),
                targetCoordinate: target,
                systemImage: transitSymbol(for: step.properties.type)
            )
        }
        if let firstPoint = allCoordinates.first {
            let walkingDistance = GeoMath.distanceMeters(from: origin, to: firstPoint)
            if walkingDistance > 15 {
                steps.insert(
                    NavigationRouteStep(
                        instruction: "승차 지점까지 걸어가세요",
                        distance: walkingDistance,
                        targetCoordinate: firstPoint,
                        systemImage: NavigationMode.walking.systemImage
                    ),
                    at: 0
                )
            }
        }
        if let lastPoint = allCoordinates.last {
            let walkingDistance = GeoMath.distanceMeters(from: lastPoint, to: destination.coordinate)
            if walkingDistance > 15 {
                steps.append(
                    NavigationRouteStep(
                        instruction: "하차 후 카페까지 걸어가세요",
                        distance: walkingDistance,
                        targetCoordinate: destination.coordinate,
                        systemImage: NavigationMode.walking.systemImage
                    )
                )
            }
        }

        var details: [String] = []
        if route.properties.transfers > 0 { details.append("환승 \(route.properties.transfers)회") }
        if let fare = route.properties.fare?.value, fare > 0 {
            details.append(fare.formatted(.currency(code: "KRW").precision(.fractionLength(0))))
        }

        return NavigationRoute(
            polyline: try polyline(from: allCoordinates, origin: origin, destination: destination.coordinate),
            steps: steps,
            distance: CLLocationDistance(route.properties.totalDistance),
            expectedTravelTime: TimeInterval(route.properties.totalTime),
            landingURL: response.properties.flatMap { URL(string: $0.landingURL) },
            provider: .kakaoMap,
            detailText: details.isEmpty ? nil : details.joined(separator: " · ")
        )
    }

    private func automobileRoute(
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) async throws -> NavigationRoute {
        let response: AutomobileResponse = try await request(
            host: "apis-navi.kakaomobility.com",
            path: "/v1/directions",
            queryItems: [
                URLQueryItem(name: "origin", value: "\(origin.longitude),\(origin.latitude)"),
                URLQueryItem(name: "destination", value: "\(destination.coordinate.longitude),\(destination.coordinate.latitude)"),
                URLQueryItem(name: "priority", value: "RECOMMEND"),
                URLQueryItem(name: "summary", value: "false")
            ]
        )
        guard let route = response.routes.first, route.resultCode.map({ $0 == 0 }) ?? true else {
            throw KakaoRoutingError.noRoute
        }

        let sections = route.sections ?? []
        let coordinates = sections.flatMap(\.roads).flatMap { road -> [CLLocationCoordinate2D] in
            var points: [CLLocationCoordinate2D] = []
            var index = 0
            while road.vertexes.indices.contains(index + 1) {
                points.append(
                    CLLocationCoordinate2D(
                        latitude: road.vertexes[index + 1],
                        longitude: road.vertexes[index]
                    )
                )
                index += 2
            }
            return points
        }
        let guides = sections.flatMap(\.guides).filter { $0.type != 100 }
        let steps = guides.map { guide in
            NavigationRouteStep(
                instruction: guide.guidance.isEmpty ? (guide.name.isEmpty ? "경로를 따라 이동하세요" : guide.name) : guide.guidance,
                distance: CLLocationDistance(guide.distance),
                targetCoordinate: CLLocationCoordinate2D(latitude: guide.y, longitude: guide.x),
                systemImage: NavigationMode.automobile.systemImage
            )
        }

        return NavigationRoute(
            polyline: try polyline(from: coordinates, origin: origin, destination: destination.coordinate),
            steps: steps,
            distance: CLLocationDistance(route.summary.distance),
            expectedTravelTime: TimeInterval(route.summary.duration),
            landingURL: kakaoAutomobileLandingURL(from: origin, to: destination),
            provider: .kakaoMobility,
            detailText: route.summary.fare?.toll.flatMap { $0 > 0 ? "통행료 \($0.formatted())원" : nil }
        )
    }

    private func request<Response: Decodable>(
        host: String,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        guard let url = components.url else { throw KakaoRoutingError.malformedResponse }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 12

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw KakaoRoutingError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw KakaoRoutingError.malformedResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw KakaoRoutingError.unauthorized
        case 429: throw KakaoRoutingError.quotaExceeded
        default: throw KakaoRoutingError.badResponse(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw KakaoRoutingError.malformedResponse
        }
    }

    private func coordinateQuery(
        from origin: CLLocationCoordinate2D,
        to destination: Cafe
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "start_x", value: String(origin.longitude)),
            URLQueryItem(name: "start_y", value: String(origin.latitude)),
            URLQueryItem(name: "s_name", value: "현재 위치"),
            URLQueryItem(name: "end_x", value: String(destination.coordinate.longitude)),
            URLQueryItem(name: "end_y", value: String(destination.coordinate.latitude)),
            URLQueryItem(name: "e_name", value: destination.name),
            URLQueryItem(name: "input_coord", value: "WGS84"),
            URLQueryItem(name: "output_coord", value: "WGS84")
        ]
    }

    private func coordinates(from points: [[Double]]) -> [CLLocationCoordinate2D] {
        points.compactMap { point in
            guard point.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
    }

    private func polyline(
        from coordinates: [CLLocationCoordinate2D],
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D
    ) throws -> MKPolyline {
        var points = coordinates
        if points.isEmpty { points = [origin, destination] }
        if let first = points.first, GeoMath.distanceMeters(from: origin, to: first) > 5 {
            points.insert(origin, at: 0)
        }
        if let last = points.last, GeoMath.distanceMeters(from: last, to: destination) > 5 {
            points.append(destination)
        }
        guard points.count >= 2 else { throw KakaoRoutingError.malformedResponse }
        return MKPolyline(coordinates: points, count: points.count)
    }

    private func transitSymbol(for type: String) -> String {
        switch type {
        case "BUS": "bus.fill"
        case "SUBWAY": "tram.fill"
        default: "figure.walk"
        }
    }

    private func kakaoAutomobileLandingURL(from origin: CLLocationCoordinate2D, to destination: Cafe) -> URL? {
        var components = URLComponents(string: "https://map.kakao.com/link/to/\(destination.name),\(destination.coordinate.latitude),\(destination.coordinate.longitude)")
        components?.queryItems = [
            URLQueryItem(name: "from", value: "현재 위치"),
            URLQueryItem(name: "fromX", value: String(origin.longitude)),
            URLQueryItem(name: "fromY", value: String(origin.latitude))
        ]
        return components?.url
    }
}

// MARK: - 도보·자전거

private struct ActiveResponse: Decodable {
    let status: String
    let route: ActiveRoute?
}

private struct ActiveRoute: Decodable {
    let properties: ActiveProperties
    let legs: [ActiveLeg]
}

private struct ActiveProperties: Decodable {
    let totalDistance: Int
    let totalTime: Int
    let landingUrl: String
}

private struct ActiveLeg: Decodable {
    let steps: [ActiveStep]
}

private struct ActiveStep: Decodable {
    let properties: ActiveStepProperties
    let path: RoutePath
}

private struct ActiveStepProperties: Decodable {
    let distance: Int
    let guidance: String
}

private struct RoutePath: Decodable {
    let points: [[Double]]
}

// MARK: - 대중교통

private struct TransitResponse: Decodable {
    let status: String
    let properties: TransitTopProperties?
    let routes: [TransitRoute]?
}

private struct TransitTopProperties: Decodable {
    let landingURL: String
}

private struct TransitRoute: Decodable {
    let properties: TransitRouteProperties
    let steps: [TransitStep]
}

private struct TransitRouteProperties: Decodable {
    let totalDistance: Int
    let totalTime: Int
    let transfers: Int
    let fare: TransitFare?
}

private struct TransitFare: Decodable {
    let value: Int
}

private struct TransitStep: Decodable {
    let properties: TransitStepProperties
    let path: RoutePath
}

private struct TransitStepProperties: Decodable {
    let guidance: String
    let type: String
    let distance: Int
}

// MARK: - 자동차

private struct AutomobileResponse: Decodable {
    let routes: [AutomobileRoute]
}

private struct AutomobileRoute: Decodable {
    let resultCode: Int?
    let summary: AutomobileSummary
    let sections: [AutomobileSection]?

    enum CodingKeys: String, CodingKey {
        case resultCode = "result_code"
        case summary
        case sections
    }
}

private struct AutomobileSummary: Decodable {
    let distance: Int
    let duration: Int
    let fare: AutomobileFare?
}

private struct AutomobileFare: Decodable {
    let toll: Int?
}

private struct AutomobileSection: Decodable {
    let roads: [AutomobileRoad]
    let guides: [AutomobileGuide]
}

private struct AutomobileRoad: Decodable {
    let vertexes: [Double]
}

private struct AutomobileGuide: Decodable {
    let name: String
    let x: Double
    let y: Double
    let distance: Int
    let type: Int
    let guidance: String
}
