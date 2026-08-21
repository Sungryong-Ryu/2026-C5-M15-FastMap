import CoreLocation
import Foundation
import MapKit

struct NearbyPlaceService {
    func searchPlaces(
        query: String,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 6000
    ) async -> [Place] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedQuery
        request.region = MKCoordinateRegion(
            center: origin,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return normalizedPlaces(
                from: response.mapItems,
                category: .searchResult,
                origin: origin,
                radiusMeters: radiusMeters
            )
        } catch {
            return []
        }
    }

    /// 카테고리 하나의 주변 장소를 찾습니다.
    ///
    /// Apple POI 분류가 있으면 그것으로 먼저 찾고, 결과가 적으면 카테고리 이름(검색어)으로
    /// 자연어 검색을 덧붙여 보강합니다. 사용자가 직접 만든 카테고리는 대부분 POI 분류가 없어서
    /// 자연어 검색이 주 경로가 됩니다.
    func searchPlaces(
        category: PlaceCategory,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 3000
    ) async -> [Place] {
        var collected: [Place] = []

        if let poiCategories = category.pointOfInterestCategories {
            collected = await searchPlacesByPOI(
                category,
                poiCategories: poiCategories,
                around: origin,
                radiusMeters: radiusMeters
            )
        }

        // POI 분류가 없거나, 지역에 따라 분류가 붙지 않아 결과가 빈약한 경우를 보강합니다.
        if collected.count < 8 {
            let byName = await searchPlacesByCategoryName(category, around: origin, radiusMeters: radiusMeters)
            collected = merge(collected, byName)
        }

        return Array(
            collected
                .sorted { $0.distanceMeters < $1.distanceMeters }
                .prefix(20)
        )
    }

    private func searchPlacesByPOI(
        _ category: PlaceCategory,
        poiCategories: [MKPointOfInterestCategory],
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> [Place] {
        let request = MKLocalPointsOfInterestRequest(center: origin, radius: radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)

        do {
            let response = try await MKLocalSearch(request: request).start()
            return normalizedPlaces(
                from: response.mapItems,
                category: category,
                origin: origin,
                radiusMeters: radiusMeters
            )
        } catch {
            // 일부 지역은 모든 장소에 Apple POI 분류를 붙이지 않습니다. 자연어 검색으로 넘어갑니다.
            return []
        }
    }

    private func merge(_ lhs: [Place], _ rhs: [Place]) -> [Place] {
        var seenIDs = Set(lhs.map(\.id))
        var seenPins = Set(lhs.map { "\($0.name)|\(Int($0.coordinate.latitude * 10000))|\(Int($0.coordinate.longitude * 10000))" })
        var result = lhs

        for place in rhs {
            let pin = "\(place.name)|\(Int(place.coordinate.latitude * 10000))|\(Int(place.coordinate.longitude * 10000))"
            guard seenIDs.insert(place.id).inserted, seenPins.insert(pin).inserted else { continue }
            result.append(place)
        }
        return result
    }

    /// 카테고리 이름(검색어)으로 주변을 찾습니다.
    ///
    /// 사용자가 만든 카테고리는 Apple POI 분류가 없는 경우가 대부분이라 이 경로가 핵심입니다.
    /// 한 번에 못 찾는 경우가 많아서 단계적으로 조건을 완화합니다.
    private func searchPlacesByCategoryName(
        _ category: PlaceCategory,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> [Place] {
        let query = category.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        // 1차: 반경 안으로 강하게 제한. 가장 정확합니다.
        var places = await naturalLanguageSearch(
            query: query,
            category: category,
            origin: origin,
            radiusMeters: radiusMeters,
            strictRegion: true
        )
        if !places.isEmpty { return places }

        // 2차: 지역 제한을 풀고 반경을 넓혀서 다시 찾습니다.
        // 흔치 않은 업종은 3km 안에 아예 없을 수 있습니다.
        places = await naturalLanguageSearch(
            query: query,
            category: category,
            origin: origin,
            radiusMeters: radiusMeters * 3,
            strictRegion: false
        )
        if !places.isEmpty { return places }

        // 3차: 카테고리 이름이 검색어와 다르면 이름으로도 한 번 더 시도합니다.
        let title = category.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.caseInsensitiveCompare(query) != .orderedSame else { return [] }

        return await naturalLanguageSearch(
            query: title,
            category: category,
            origin: origin,
            radiusMeters: radiusMeters * 3,
            strictRegion: false
        )
    }

    private func naturalLanguageSearch(
        query: String,
        category: PlaceCategory,
        origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        strictRegion: Bool
    ) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: origin,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        request.regionPriority = strictRegion ? .required : .default

        do {
            let response = try await MKLocalSearch(request: request).start()
            return normalizedPlaces(
                from: response.mapItems,
                category: category,
                origin: origin,
                radiusMeters: radiusMeters
            )
        } catch {
            return []
        }
    }

    private func normalizedPlaces(
        from mapItems: [MKMapItem],
        category: PlaceCategory,
        origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) -> [Place] {
        let places = mapItems.compactMap { item -> Place? in
            let coordinate = item.location.coordinate
            guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

            return Place(
                id: item.identifier?.rawValue ?? "\(category.id)-\(coordinate.latitude)-\(coordinate.longitude)",
                name: item.name ?? category.title,
                category: category,
                address: formattedAddress(for: item),
                coordinate: coordinate,
                distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
                bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate)
            )
        }

        return Array(
            places
                .filter { $0.distanceMeters <= radiusMeters }
                .sorted { $0.distanceMeters < $1.distanceMeters }
                .prefix(20)
        )
    }

    /// iOS 26부터 `MKMapItem.placemark` 대신 `address`(MKAddress)를 씁니다.
    /// 목록 한 줄에 들어가야 해서 짧은 주소를 우선합니다.
    private func formattedAddress(for item: MKMapItem) -> String {
        guard let address = item.address else { return "주소 정보 없음" }

        if let shortAddress = address.shortAddress, !shortAddress.isEmpty {
            return shortAddress
        }

        let fullAddress = address.fullAddress
        return fullAddress.isEmpty ? "주소 정보 없음" : fullAddress
    }
}

enum PreviewPlaceFactory {
    static func places(for category: PlaceCategory, around origin: CLLocationCoordinate2D) -> [Place] {
        let offsets: [(Double, Double)] = [
            (0.0012, 0.0007),
            (-0.0009, 0.0011),
            (0.0017, -0.0010)
        ]

        return offsets.enumerated().map { index, offset in
            let coordinate = CLLocationCoordinate2D(
                latitude: origin.latitude + offset.0,
                longitude: origin.longitude + offset.1
            )
            return Place(
                id: "\(category.id)-mock-\(index)",
                name: "근처 \(category.title) \(index + 1)",
                category: category,
                address: "Xcode 미리보기 장소",
                coordinate: coordinate,
                distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
                bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate)
            )
        }
    }
}
