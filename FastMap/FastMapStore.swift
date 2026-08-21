import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class FastMapStore: ObservableObject {
    @Published var selectedTab: AppTab = .radar
    @Published var places: [Place] = []
    @Published var selectedPlace: Place?
    @Published var route: MKRoute?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""


    private var lastRefreshLocation: CLLocationCoordinate2D?
    private var lastRefreshCategoryIDs: [String] = []

    func refreshPlaces(
        from location: CLLocationCoordinate2D,
        categories: [PlaceCategory],
        force: Bool = false
    ) async {
        let categoryIDs = categories.map(\.id)
        let categoriesChanged = categoryIDs != lastRefreshCategoryIDs

        if !force, !categoriesChanged, let lastRefreshLocation {
            let moved = GeoMath.distanceMeters(from: lastRefreshLocation, to: location)
            guard moved > 70 || places.isEmpty else { return }
        }

        lastRefreshCategoryIDs = categoryIDs

        guard !categories.isEmpty else {
            places = []
            selectedPlace = nil
            route = nil
            lastRefreshLocation = location
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let service = NearbyPlaceService()
        let nestedPlaces = await withTaskGroup(of: [Place].self) { group in
            for category in categories {
                group.addTask {
                    await service.searchPlaces(category: category, around: location)
                }
            }

            var results: [[Place]] = []
            for await categoryPlaces in group {
                results.append(categoryPlaces)
            }
            return results
        }

        let refreshedPlaces = nestedPlaces
            .flatMap { $0 }
            .sorted { $0.distanceMeters < $1.distanceMeters }

        // 자동 선택하지 않습니다.
        // 선택이 생기면 카메라가 그 장소로 이동해 버려서, 앱을 켤 때 현위치가 아닌 곳이 보였습니다.
        let previousSelectionID = selectedPlace?.id
        places = refreshedPlaces
        selectedPlace = places.first { $0.id == previousSelectionID }
        lastRefreshLocation = location
        await updateRoute(from: location)
    }

    func select(_ place: Place, from location: CLLocationCoordinate2D) async {
        selectedPlace = place
        await updateRoute(from: location)
    }

    func updateRoute(from location: CLLocationCoordinate2D) async {
        guard let selectedPlace else {
            route = nil
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: location.latitude, longitude: location.longitude),
            address: nil
        )
        request.destination = selectedPlace.mapItem
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
        } catch {
            route = nil
        }
    }

    static var preview: FastMapStore {
        let store = FastMapStore()
        store.places = PreviewPlaceFactory.places(for: .restroom, around: .seoulCityHall)
        store.selectedPlace = store.places.first
        return store
    }
}
