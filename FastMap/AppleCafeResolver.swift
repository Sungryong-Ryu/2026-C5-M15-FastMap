//
//  AppleCafeResolver.swift
//  WhereismyAHAH
//
//  Apple 지도(MKLocalSearch)로 카페를 찾습니다. 두 가지 일을 합니다.
//
//  1. 즐겨찾기 저장용 변환 — Kakao 카페는 약관상 저장할 수 없습니다.
//     사용자가 즐겨찾기를 누르면 그 순간 같은 카페를 Apple 지도에서 다시 찾아
//     `.apple` 카페로 바꾼 뒤 저장합니다. `resolve(_:)`가 그 일을 합니다.
//
//  2. 해외 지역의 기본 검색 및 국내 대체 경로 — 검색 중심이 해외이거나 Kakao API 키가
//     없거나 한도를 넘겼을 때 `nearbyCafes(around:)`가 Apple 데이터로 화면을 채웁니다.
//

import CoreLocation
import Foundation
import MapKit

struct AppleCafeResolver {

    // MARK: - 즐겨찾기용 변환

    /// Kakao 카페와 같은 곳을 Apple 지도에서 찾아 `.apple` 카페로 돌려줍니다.
    ///
    /// 상호명으로 좁은 반경을 뒤진 뒤, 좌표가 가장 가까운 후보를 고릅니다.
    /// 두 서비스의 좌표가 조금씩 어긋나므로 이름이 정확히 같기를 기대하지 않고
    /// 거리로 판단합니다. 아무것도 못 찾으면 nil입니다.
    func resolve(_ cafe: Cafe, toleranceMeters: CLLocationDistance = 120) async -> Cafe? {
        if cafe.source == .apple { return cafe }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cafe.name
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: cafe.coordinate,
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
        request.regionPriority = .required

        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }

        let candidates = response.mapItems
            .map { ($0, GeoMath.distanceMeters(from: cafe.coordinate, to: $0.location.coordinate)) }
            .filter { $0.1 <= toleranceMeters }
            .sorted { $0.1 < $1.1 }

        guard let best = candidates.first?.0 else { return nil }

        return makeCafe(
            from: best,
            origin: cafe.coordinate,
            distanceOverride: cafe.distanceMeters,
            bearingOverride: cafe.bearingDegrees
        )
    }

    // MARK: - 해외 검색 및 국내 대체 경로

    /// Apple MapKit 데이터만으로 주변 카페를 찾습니다.
    func nearbyCafes(
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 2_000
    ) async -> [Cafe] {
        var collected = await pointsOfInterestCafes(around: origin, radiusMeters: radiusMeters)

        // 지역에 따라 Apple이 POI 분류를 안 붙이는 곳이 있어 자연어 검색으로 보강합니다.
        if collected.count < 10 {
            let byName = await search(query: "카페", around: origin, radiusMeters: radiusMeters)
            collected = merge(collected, byName)
        }

        return collected
            .filter { $0.distanceMeters <= radiusMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// 사용자가 입력한 검색어로 찾습니다.
    func search(
        query: String,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 5_000
    ) async -> [Cafe] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: origin,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems
            .compactMap { makeCafe(from: $0, origin: origin) }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    private func pointsOfInterestCafes(
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> [Cafe] {
        let request = MKLocalPointsOfInterestRequest(center: origin, radius: radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.cafe])

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { makeCafe(from: $0, origin: origin) }
    }

    // MARK: - 변환

    private func makeCafe(
        from item: MKMapItem,
        origin: CLLocationCoordinate2D,
        distanceOverride: Double? = nil,
        bearingOverride: Double? = nil
    ) -> Cafe? {
        let coordinate = item.location.coordinate
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        let name = item.name ?? "이름 없는 카페"
        let address = formattedAddress(for: item)

        return Cafe(
            id: item.identifier?.rawValue ?? "apple-\(coordinate.latitude)-\(coordinate.longitude)",
            name: name,
            address: address,
            roadAddress: nil,
            phone: item.phoneNumber,
            categoryName: item.pointOfInterestCategory?.rawValue,
            placeURL: item.url,
            coordinate: coordinate,
            distanceMeters: distanceOverride ?? GeoMath.distanceMeters(from: origin, to: coordinate),
            bearingDegrees: bearingOverride ?? GeoMath.bearingDegrees(from: origin, to: coordinate),
            tags: CafeTagClassifier.tags(
                name: name,
                categoryName: item.pointOfInterestCategory?.rawValue,
                coordinate: coordinate
            ),
            source: .apple
        )
    }

    /// iOS 26부터 `MKMapItem.placemark` 대신 `address`(MKAddress)를 씁니다.
    /// 목록 한 줄에 들어가야 해서 짧은 주소를 우선합니다.
    private func formattedAddress(for item: MKMapItem) -> String {
        guard let address = item.address else { return "주소 정보 없음" }
        if let shortAddress = address.shortAddress, !shortAddress.isEmpty { return shortAddress }
        let fullAddress = address.fullAddress
        return fullAddress.isEmpty ? "주소 정보 없음" : fullAddress
    }

    private func merge(_ lhs: [Cafe], _ rhs: [Cafe]) -> [Cafe] {
        var seenIDs = Set(lhs.map(\.id))
        var seenPins = Set(lhs.map(\.dedupeKey))
        var result = lhs
        for cafe in rhs where seenIDs.insert(cafe.id).inserted && seenPins.insert(cafe.dedupeKey).inserted {
            result.append(cafe)
        }
        return result
    }
}

// MARK: - 미리보기

enum PreviewCafeFactory {
    static func cafes(around origin: CLLocationCoordinate2D) -> [Cafe] {
        let samples: [(String, Double, Double, Set<CafeTag>)] = [
            ("스타벅스 시청점", 0.0012, 0.0007, [.franchise]),
            ("한강뷰 로스터리", -0.0009, 0.0011, [.independent, .waterfront, .large]),
            ("소금집 베이커리", 0.0017, -0.0010, [.independent, .bakery, .cozy])
        ]

        return samples.enumerated().map { index, sample in
            let coordinate = CLLocationCoordinate2D(
                latitude: origin.latitude + sample.1,
                longitude: origin.longitude + sample.2
            )
            return Cafe(
                id: "preview-\(index)",
                name: sample.0,
                address: "Xcode 미리보기 장소",
                categoryName: "음식점 > 카페",
                coordinate: coordinate,
                distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
                bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate),
                tags: sample.3,
                source: .preview
            )
        }
    }
}
