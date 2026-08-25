//
//  RegionScope.swift
//  CoFFMap
//
//  "이 지역 전체"가 어디까지인지 정합니다.
//
//  거리 칩에서 "전체"를 고르면 반경이 아니라 **행정 구역** 단위로 카페를 봅니다.
//  구역을 어디까지로 볼지는 지역마다 다릅니다.
//  - 특별시·광역시: 자치구 하나 (서울에 있으면 "강남구")
//  - 그 밖의 도 지역: 시·군 전체 (포항에 있으면 "포항시" — 남구·북구로 쪼개지 않습니다)
//
//  구역 이름은 카카오에서 받고, 구역이 얼마나 넓은지는 Apple 지오코더로 보강합니다.
//  둘 다 실패하면 이름 접미사(구·시·군)로 어림잡습니다. 어림값이라도 있어야
//  "전체"가 아무 일도 하지 않는 상황을 막을 수 있습니다.
//

import CoreLocation
import Foundation
import MapKit

enum SearchTerritory: Equatable, Sendable {
    case southKorea
    case international
}

/// 검색 중심 좌표가 국내인지 해외인지 판별합니다.
///
/// 국가 경계는 단순 위·경도 사각형으로 나누면 일본 서부나 중국 연안을 국내로 오인할 수
/// 있으므로 MapKit 역지오코딩의 ISO 국가 코드를 우선 사용합니다. 동일 지역을 지도 조작마다
/// 다시 묻지 않도록 약 2km 격자로 메모리에만 캐시합니다.
@MainActor
final class SearchTerritoryResolver {
    private struct CacheKey: Hashable {
        let latitudeCell: Int
        let longitudeCell: Int

        init(_ coordinate: CLLocationCoordinate2D) {
            latitudeCell = Int((coordinate.latitude * 50).rounded())
            longitudeCell = Int((coordinate.longitude * 50).rounded())
        }
    }

    private var cache: [CacheKey: SearchTerritory] = [:]

    func territory(at coordinate: CLLocationCoordinate2D) async -> SearchTerritory {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return .international }

        let key = CacheKey(coordinate)
        if let cached = cache[key] { return cached }

        let countryCode = await countryCode(at: coordinate)
        let territory: SearchTerritory
        if let countryCode {
            territory = countryCode.caseInsensitiveCompare("KR") == .orderedSame
                ? .southKorea
                : .international
        } else {
            // 네트워크가 잠시 끊겨도 대한민국 내륙과 제주에서는 Kakao 검색을 유지합니다.
            // 경계가 불확실한 좌표는 해외로 보아 Kakao에 잘못 질의하지 않는 쪽을 택합니다.
            territory = Self.isClearlyInsideSouthKorea(coordinate) ? .southKorea : .international
        }

        cache[key] = territory
        return territory
    }

    private func countryCode(at coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItems = try? await request.mapItems else { return nil }
        // `regionCode`는 Swift에서 refined 이름으로 노출됩니다.
        return mapItems.first?.addressRepresentations?.__regionCode
    }

    private static func isClearlyInsideSouthKorea(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let jeju = coordinate.latitude >= 33.05 && coordinate.latitude <= 33.65
            && coordinate.longitude >= 125.95 && coordinate.longitude <= 127.20
        if jeju { return true }

        // 대한민국 본토의 해안선과 군사분계선을 넉넉하게 단순화한 다각형입니다.
        // 역지오코딩 실패 시에만 사용하는 보조 판단이므로 국경 밖 오판을 줄이는 쪽으로 잡습니다.
        let mainland = [
            CLLocationCoordinate2D(latitude: 38.63, longitude: 128.38),
            CLLocationCoordinate2D(latitude: 38.31, longitude: 128.62),
            CLLocationCoordinate2D(latitude: 37.10, longitude: 129.42),
            CLLocationCoordinate2D(latitude: 36.10, longitude: 129.58),
            CLLocationCoordinate2D(latitude: 35.15, longitude: 129.40),
            CLLocationCoordinate2D(latitude: 34.62, longitude: 128.72),
            CLLocationCoordinate2D(latitude: 34.22, longitude: 126.50),
            CLLocationCoordinate2D(latitude: 34.70, longitude: 125.85),
            CLLocationCoordinate2D(latitude: 36.55, longitude: 125.90),
            CLLocationCoordinate2D(latitude: 37.65, longitude: 125.85),
            CLLocationCoordinate2D(latitude: 38.05, longitude: 126.25),
            CLLocationCoordinate2D(latitude: 38.40, longitude: 126.75)
        ]
        return contains(coordinate, in: mainland)
    }

    private static func contains(
        _ coordinate: CLLocationCoordinate2D,
        in polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previous = polygon.count - 1

        for current in polygon.indices {
            let lhs = polygon[current]
            let rhs = polygon[previous]
            let crossesLatitude = (lhs.latitude > coordinate.latitude) != (rhs.latitude > coordinate.latitude)
            if crossesLatitude {
                let boundaryLongitude = (rhs.longitude - lhs.longitude)
                    * (coordinate.latitude - lhs.latitude)
                    / (rhs.latitude - lhs.latitude)
                    + lhs.longitude
                if coordinate.longitude < boundaryLongitude { isInside.toggle() }
            }
            previous = current
        }
        return isInside
    }
}

/// 카페를 훑을 행정 구역 하나.
struct RegionScope: Equatable, Sendable {
    /// 화면에 짧게 쓰는 이름. "강남구", "포항시".
    let title: String
    /// 상위 구역까지 붙인 이름. "서울특별시 강남구".
    let fullTitle: String
    /// 구역의 대표 좌표.
    let center: CLLocationCoordinate2D
    /// 구역을 덮는 대략적인 반경.
    let radiusMeters: CLLocationDistance
}

/// 좌표 → 행정 구역.
///
/// 같은 구역을 다시 물어보는 일이 잦아서(거리 칩을 껐다 켤 때마다) 메모리에 캐시합니다.
/// 카카오 응답은 저장할 수 없으므로 디스크에는 아무것도 남기지 않습니다.
@MainActor
final class RegionScopeResolver {

    /// 한 행정 구역을 여러 검색 원으로 나눠 훑을 때 허용하는 전체 반경.
    /// Kakao의 개별 호출 반경 상한은 20km지만, 표본 지점을 나누므로 시·군은 더 넓게
    /// 덮을 수 있습니다.
    static let maxRadiusMeters: CLLocationDistance = 40_000
    private static let minRadiusMeters: CLLocationDistance = 1_500

    private var cache: [String: RegionScope] = [:]
    private let territoryResolver: SearchTerritoryResolver

    init(territoryResolver: SearchTerritoryResolver) {
        self.territoryResolver = territoryResolver
    }

    /// 좌표가 속한 구역 전체.
    func scope(at coordinate: CLLocationCoordinate2D) async -> RegionScope? {
        guard let name = await regionName(at: coordinate) else { return nil }
        if let cached = cache[name.fullTitle] { return cached }

        // 구역의 중심과 넓이는 이름으로 다시 지오코딩해서 얻습니다.
        // 사용자가 구역 가장자리에 서 있어도 반대쪽 끝까지 훑으려면 필요한 값입니다.
        let placemark = await geocode(name.fullTitle)
        let center = placemark?.location?.coordinate ?? coordinate
        let geocodedRadius = (placemark?.region as? CLCircularRegion)?.radius ?? 0
        // Apple이 너무 작은 원을 돌려줘도 시·군의 외곽을 놓치지 않도록 접미사 기반
        // 어림값을 하한으로 사용합니다.
        let radius = max(geocodedRadius, name.estimatedRadius)

        let scope = RegionScope(
            title: name.title,
            fullTitle: name.fullTitle,
            center: center,
            radiusMeters: min(max(radius, Self.minRadiusMeters), Self.maxRadiusMeters)
        )
        cache[name.fullTitle] = scope
        return scope
    }

    /// 지도에서 본 지역의 이름만 필요할 때. 넓이는 화면이 정하므로 묻지 않습니다.
    func title(at coordinate: CLLocationCoordinate2D) async -> String? {
        await regionName(at: coordinate)?.title
    }

    // MARK: - 이름

    private struct RegionName {
        let title: String
        let fullTitle: String
        let estimatedRadius: CLLocationDistance
    }

    private func regionName(at coordinate: CLLocationCoordinate2D) async -> RegionName? {
        let territory = await territoryResolver.territory(at: coordinate)
        if territory == .southKorea,
           let kakao = KakaoLocalService(),
           let region = try? await kakao.region(at: coordinate),
           let name = Self.makeName(province: region.province, district: region.district) {
            return name
        }
        return await appleRegionName(at: coordinate)
    }

    /// 카카오 키가 없거나 호출이 실패했을 때. 국내 주소에서 어느 필드에 자치구가 들어오는지가
    /// 일정하지 않아, locality와 subLocality를 순서대로 살펴봅니다.
    private func appleRegionName(at coordinate: CLLocationCoordinate2D) async -> RegionName? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }

        let province = placemark.administrativeArea ?? ""
        var district = ""
        if let locality = placemark.locality, !locality.isEmpty, locality != province {
            district = locality
        } else if let subLocality = placemark.subLocality, !subLocality.isEmpty {
            district = subLocality
        }

        return Self.makeName(province: province, district: district)
    }

    /// 카카오가 주는 시도·시군구를 사람이 말하는 구역 하나로 정리합니다.
    private static func makeName(province: String, district: String) -> RegionName? {
        let province = province.trimmingCharacters(in: .whitespaces)
        var district = district.trimmingCharacters(in: .whitespaces)
        guard !province.isEmpty else { return nil }

        // 특별시·광역시는 자치구가 생활권 단위입니다. 도 지역은 시·군 전체가 자연스럽고,
        // 포항시 남구처럼 일반구까지 쪼개면 "포항 전체"를 보려던 의도와 어긋납니다.
        let isMetropolitan = province.hasSuffix("특별시")
            || province.hasSuffix("광역시")
            || province.hasSuffix("특별자치시")

        if !isMetropolitan, let cityEnd = district.range(of: "시 ")?.upperBound {
            district = String(district[..<cityEnd]).trimmingCharacters(in: .whitespaces)
        }

        let title = district.isEmpty ? province : district
        let fullTitle = district.isEmpty ? province : "\(province) \(district)"

        return RegionName(
            title: title,
            fullTitle: fullTitle,
            estimatedRadius: estimatedRadius(for: title)
        )
    }

    /// 지오코더가 구역 경계를 안 줄 때 쓰는 어림값.
    private static func estimatedRadius(for title: String) -> CLLocationDistance {
        if title.hasSuffix("구") { return 7_000 }
        if title.hasSuffix("군") { return 35_000 }
        if title.hasSuffix("시") { return 25_000 }
        // 읍면동까지 내려간 경우(Apple 대체 경로)와 세종처럼 시군구가 없는 경우.
        if title.hasSuffix("동") || title.hasSuffix("읍") || title.hasSuffix("면") { return 3_000 }
        return 20_000
    }

    // MARK: - 넓이

    private func geocode(_ address: String) async -> CLPlacemark? {
        try? await CLGeocoder().geocodeAddressString(address).first
    }
}
