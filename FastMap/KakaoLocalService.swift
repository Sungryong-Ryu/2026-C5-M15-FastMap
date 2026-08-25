//
//  KakaoLocalService.swift
//  CoFFMap
//
//  Kakao Local API로 주변 카페를 찾습니다.
//
//  왜 Apple 지도가 아니라 Kakao인가:
//  MKLocalSearch의 국내 카페 데이터는 상호가 빠지거나 분류가 안 붙는 곳이 많습니다.
//  Kakao는 CE7(카페) 분류로 반경 안을 통째로 받아올 수 있고 분류 문자열도 상세해서,
//  태그를 붙일 단서가 훨씬 많습니다.
//
//  ⚠️ 저장 금지
//  카카오 공식 답변 기준으로 Local API 응답은 원본이든 가공본이든 기기·서버에 저장할 수 없고
//  실시간 호출로만 쓸 수 있습니다. 그래서 이 서비스가 만드는 Cafe는 전부 `source == .kakao`이고,
//  `SavedCafeStore`는 `.kakao` 카페를 그대로 저장하지 않습니다. 즐겨찾기는 저장 직전에
//  `AppleCafeResolver`가 Apple 지도에서 같은 카페를 다시 찾아 `.apple` 값으로 바꿉니다.
//

import CoreLocation
import Foundation

enum KakaoLocalError: LocalizedError {
    case missingAPIKey
    case unauthorized
    case quotaExceeded
    case badResponse(Int)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Kakao REST API 키가 없습니다. Secrets.plist를 확인해 주세요."
        case .unauthorized:
            "Kakao API 키가 올바르지 않습니다."
        case .quotaExceeded:
            "오늘 Kakao API 호출 한도를 다 썼습니다."
        case .badResponse(let code):
            "Kakao 응답 오류 (\(code))"
        case .transport:
            "네트워크에 연결할 수 없습니다."
        }
    }
}

/// Kakao `rect` 파라미터에 넘기는 경위도 사각형.
struct KakaoSearchRectangle: Equatable, Sendable {
    let west: CLLocationDegrees
    let south: CLLocationDegrees
    let east: CLLocationDegrees
    let north: CLLocationDegrees

    var queryValue: String { "\(west),\(south),\(east),\(north)" }
}

/// 한 검색 사각형의 결과. `isSaturated`면 Kakao의 45곳 노출 상한에 닿은 상태입니다.
struct KakaoCafeBatch {
    let cafes: [Cafe]
    let isSaturated: Bool
}

struct KakaoLocalService {
    /// 카카오 장소 분류 코드 중 카페.
    private static let cafeCategoryCode = "CE7"
    private static let host = "dapi.kakao.com"
    /// Kakao가 허용하는 한 페이지 최대 개수.
    private static let pageSize = 15
    /// 한 검색 조건에서 실제로 넘겨주는 장소의 상한.
    private static let maxPageableCount = 45
    /// Kakao radius 파라미터의 상한.
    private static let maxRadius: CLLocationDistance = 20_000

    private let apiKey: String
    private let session: URLSession

    init?(apiKey: String? = AppSecrets.kakaoRESTAPIKey, session: URLSession = .shared) {
        guard let apiKey else { return nil }
        self.apiKey = apiKey
        self.session = session
    }

    // MARK: - 주변 카페

    /// 반경 안의 카페를 가까운 순으로 가져옵니다.
    ///
    /// 한 페이지가 15개뿐이라 여러 페이지를 동시에 부릅니다. 이 메서드 자체는 최대
    /// 45곳이며, 필터용 전체 수집은 포화 영역을 재분할하는 `categoryCafeBatch`를 씁니다.
    func nearbyCafes(
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 2_000,
        pages: Int = 3
    ) async throws -> [Cafe] {
        let radius = min(radiusMeters, Self.maxRadius)
        return try await cafeBatch(
            path: "/v2/local/search/category.json",
            queryItems: [
                URLQueryItem(name: "category_group_code", value: Self.cafeCategoryCode),
                URLQueryItem(name: "x", value: String(origin.longitude)),
                URLQueryItem(name: "y", value: String(origin.latitude)),
                URLQueryItem(name: "radius", value: String(Int(radius))),
                URLQueryItem(name: "sort", value: "distance")
            ],
            origin: origin,
            pages: pages
        ).cafes
    }

    /// 사각형 안의 카페와 45곳 노출 상한에 닿았는지를 함께 돌려줍니다.
    /// 상한에 닿은 사각형은 `CafeStore`가 더 작은 네 구역으로 나눠 다시 묻습니다.
    func categoryCafeBatch(
        in rectangle: KakaoSearchRectangle,
        origin: CLLocationCoordinate2D
    ) async throws -> KakaoCafeBatch {
        try await cafeBatch(
            path: "/v2/local/search/category.json",
            queryItems: [
                URLQueryItem(name: "category_group_code", value: Self.cafeCategoryCode),
                URLQueryItem(name: "x", value: String(origin.longitude)),
                URLQueryItem(name: "y", value: String(origin.latitude)),
                URLQueryItem(name: "rect", value: rectangle.queryValue),
                URLQueryItem(name: "sort", value: "distance")
            ],
            origin: origin,
            pages: 3
        )
    }

    // MARK: - 키워드 검색

    /// "감성카페", "베이커리 카페" 같은 검색어로 후보를 넓힙니다.
    ///
    /// 반경 안을 전부 받아 상호명으로 걸러내는 것만으로는, 이름에 단서가 없는 곳을 놓칩니다.
    /// 카카오 검색 색인은 상호명 말고도 잡아 주는 게 있어서 한 번 더 돌릴 값이 있습니다.
    func searchCafes(
        query: String,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 2_000,
        pages: Int = 1,
        restrictToCafes: Bool = true
    ) async throws -> [Cafe] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let radius = min(radiusMeters, Self.maxRadius)

        var items = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "x", value: String(origin.longitude)),
            URLQueryItem(name: "y", value: String(origin.latitude)),
            URLQueryItem(name: "radius", value: String(Int(radius))),
            URLQueryItem(name: "sort", value: "distance")
        ]
        if restrictToCafes {
            items.append(URLQueryItem(name: "category_group_code", value: Self.cafeCategoryCode))
        }
        return try await cafeBatch(
            path: "/v2/local/search/keyword.json",
            queryItems: items,
            origin: origin,
            pages: pages
        ).cafes
    }

    /// 유형 보강 키워드도 45곳 상한을 알 수 있어야 같은 방식으로 영역을 재분할할 수 있습니다.
    func searchCafeBatch(
        query: String,
        in rectangle: KakaoSearchRectangle,
        origin: CLLocationCoordinate2D
    ) async throws -> KakaoCafeBatch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return KakaoCafeBatch(cafes: [], isSaturated: false) }

        return try await cafeBatch(
            path: "/v2/local/search/keyword.json",
            queryItems: [
                URLQueryItem(name: "query", value: trimmed),
                URLQueryItem(name: "category_group_code", value: Self.cafeCategoryCode),
                URLQueryItem(name: "x", value: String(origin.longitude)),
                URLQueryItem(name: "y", value: String(origin.latitude)),
                URLQueryItem(name: "rect", value: rectangle.queryValue),
                URLQueryItem(name: "sort", value: "distance")
            ],
            origin: origin,
            pages: 3
        )
    }

    // MARK: - 좌표 → 행정 구역

    /// 좌표가 속한 행정 구역 이름을 돌려줍니다. "경상북도 / 포항시 남구 / 대잠동" 같은 형태입니다.
    ///
    /// 여기에 Apple의 `CLGeocoder`를 쓰지 않는 이유: 국내 주소에서 `locality`와 `subLocality`에
    /// 무엇이 들어오는지가 지역마다 달라 "자치구"를 안정적으로 집어낼 수 없습니다.
    /// 카카오는 시도·시군구·읍면동을 분리해서 주므로 그대로 믿을 수 있습니다.
    func region(at coordinate: CLLocationCoordinate2D) async throws -> KakaoRegion? {
        let data = try await perform(
            path: "/v2/local/geo/coord2regioncode.json",
            queryItems: [
                URLQueryItem(name: "x", value: String(coordinate.longitude)),
                URLQueryItem(name: "y", value: String(coordinate.latitude))
            ]
        )

        let documents = try JSONDecoder().decode(RegionResponse.self, from: data).documents
        // 행정동("H")이 사람이 말하는 구역에 가깝습니다. 없으면 법정동("B")으로 갑니다.
        let document = documents.first { $0.regionType == "H" } ?? documents.first
        guard let document, !document.depth1.isEmpty else { return nil }

        return KakaoRegion(
            province: document.depth1,
            district: document.depth2,
            town: document.depth3
        )
    }

    // MARK: - 호출

    private func cafeBatch(
        path: String,
        queryItems: [URLQueryItem],
        origin: CLLocationCoordinate2D,
        pages: Int
    ) async throws -> KakaoCafeBatch {
        let pageSize = Self.pageSize
        let payloads = try await withThrowingTaskGroup(of: Data.self) { group in
            for page in 1...min(3, max(1, pages)) {
                group.addTask {
                    var pageItems = queryItems
                    pageItems.append(URLQueryItem(name: "page", value: String(page)))
                    pageItems.append(URLQueryItem(name: "size", value: String(pageSize)))
                    return try await perform(path: path, queryItems: pageItems)
                }
            }

            var all: [Data] = []
            for try await data in group { all.append(data) }
            return all
        }
        let responses = try payloads.map { try JSONDecoder().decode(SearchResponse.self, from: $0) }

        let cafes = responses
            .flatMap(\.documents)
            .map { $0.cafe(origin: origin) }

        return KakaoCafeBatch(
            cafes: dedupe(cafes).sorted { $0.distanceMeters < $1.distanceMeters },
            isSaturated: responses.contains { $0.meta.pageableCount >= Self.maxPageableCount }
        )
    }

    private func perform(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else { throw KakaoLocalError.badResponse(-1) }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw KakaoLocalError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else { throw KakaoLocalError.badResponse(-1) }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw KakaoLocalError.unauthorized
        case 429: throw KakaoLocalError.quotaExceeded
        default: throw KakaoLocalError.badResponse(http.statusCode)
        }

        return data
    }

    /// 여러 페이지·여러 검색어 결과가 겹치므로 한 번 걸러 냅니다.
    private func dedupe(_ cafes: [Cafe]) -> [Cafe] {
        var seenIDs = Set<String>()
        var seenPins = Set<String>()
        return cafes.filter { cafe in
            seenIDs.insert(cafe.id).inserted && seenPins.insert(cafe.dedupeKey).inserted
        }
    }
}

// MARK: - 행정 구역

/// 좌표가 속한 행정 구역. 카카오가 주는 단계 그대로입니다.
struct KakaoRegion: Sendable {
    /// 시도. "서울특별시", "경상북도".
    let province: String
    /// 시군구. "강남구", "포항시 남구". 세종처럼 없는 곳은 빈 문자열입니다.
    let district: String
    /// 읍면동. "역삼동".
    let town: String
}

// MARK: - 응답

private struct SearchResponse: Decodable {
    let meta: SearchMeta
    let documents: [Document]
}

private struct SearchMeta: Decodable {
    let pageableCount: Int

    enum CodingKeys: String, CodingKey {
        case pageableCount = "pageable_count"
    }
}

private struct RegionResponse: Decodable {
    let documents: [RegionDocument]
}

private struct RegionDocument: Decodable {
    /// "H"는 행정동, "B"는 법정동.
    let regionType: String
    let depth1: String
    let depth2: String
    let depth3: String

    enum CodingKeys: String, CodingKey {
        case regionType = "region_type"
        case depth1 = "region_1depth_name"
        case depth2 = "region_2depth_name"
        case depth3 = "region_3depth_name"
    }
}

private struct Document: Decodable {
    let id: String
    let placeName: String
    let categoryName: String?
    let phone: String?
    let addressName: String?
    let roadAddressName: String?
    let placeURL: String?
    /// 경도. 문자열로 옵니다.
    let x: String
    /// 위도. 문자열로 옵니다.
    let y: String

    enum CodingKeys: String, CodingKey {
        case id
        case placeName = "place_name"
        case categoryName = "category_name"
        case phone
        case addressName = "address_name"
        case roadAddressName = "road_address_name"
        case placeURL = "place_url"
        case x
        case y
    }

    func cafe(origin: CLLocationCoordinate2D) -> Cafe {
        let coordinate = CLLocationCoordinate2D(
            latitude: Double(y) ?? 0,
            longitude: Double(x) ?? 0
        )

        return Cafe(
            id: "kakao-\(id)",
            name: placeName,
            address: addressName ?? "",
            roadAddress: roadAddressName?.isEmpty == false ? roadAddressName : nil,
            phone: phone?.isEmpty == false ? phone : nil,
            categoryName: categoryName,
            placeURL: placeURL.flatMap(URL.init(string:)),
            coordinate: coordinate,
            // Kakao도 distance를 주지만, 검색 기준점과 사용자 현위치가 다를 수 있어 직접 계산합니다.
            distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate),
            tags: CafeTagClassifier.tags(
                name: placeName,
                categoryName: categoryName,
                coordinate: coordinate
            ),
            source: .kakao
        )
    }
}
