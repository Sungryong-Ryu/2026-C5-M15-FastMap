import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

@MainActor
final class FastMapStore: ObservableObject {
    @Published var selectedTab: AppTab = .radar
    @Published var selectedCategories: Set<PlaceCategory> = [.restroom, .cafe, .bank]
    @Published var focusedCategory: PlaceCategory = .restroom
    @Published var places: [Place] = []
    @Published var selectedPlace: Place?
    @Published var route: MKRoute?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var lastRefreshLocation: CLLocationCoordinate2D?

    func toggleCategory(_ category: PlaceCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
            focusedCategory = category
        }
    }

    func refreshPlaces(from location: CLLocationCoordinate2D, force: Bool = false) async {
        if !force, let lastRefreshLocation {
            let moved = GeoMath.distanceMeters(from: lastRefreshLocation, to: location)
            guard moved > 70 || places.isEmpty else { return }
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let service = NearbyPlaceService()
        let categories = selectedCategories.isEmpty ? [focusedCategory] : Array(selectedCategories)
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

        places = nestedPlaces
            .flatMap { $0 }
            .sorted { $0.distanceMeters < $1.distanceMeters }

        selectedPlace = places.first
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
