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

    func searchPlaces(
        category: PlaceCategory,
        around origin: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance = 1500
    ) async -> [Place] {
        if let poiCategories = category.pointOfInterestCategories {
            let request = MKLocalPointsOfInterestRequest(center: origin, radius: radiusMeters)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: poiCategories)

            do {
                let response = try await MKLocalSearch(request: request).start()
                return normalizedPlaces(from: response.mapItems, category: category, origin: origin, radiusMeters: radiusMeters)
            } catch {
                return []
            }
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category.koreanQuery
        request.region = MKCoordinateRegion(
            center: origin,
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            return normalizedPlaces(from: response.mapItems, category: category, origin: origin, radiusMeters: radiusMeters)
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
            let coordinate = item.placemark.coordinate
            guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

            return Place(
                id: item.identifier?.rawValue ?? "\(category.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)",
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
                .prefix(8)
        )
    }

    private func formattedAddress(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let parts = [
            placemark.locality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        return parts.isEmpty ? "주소 정보 없음" : parts.joined(separator: " ")
    }
}

private extension PlaceCategory {
    var pointOfInterestCategories: [MKPointOfInterestCategory]? {
        switch self {
        case .searchResult:
            nil
        case .restroom:
            [.restroom]
        case .cafe:
            [.cafe]
        case .bank:
            [.bank, .atm]
        case .hospital:
            [.hospital]
        case .restaurant:
            [.restaurant]
        case .pharmacy:
            [.pharmacy]
        case .convenienceStore:
            [.store, .foodMarket]
        case .parking:
            [.parking]
        }
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
                id: "\(category.rawValue)-mock-\(index)",
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
