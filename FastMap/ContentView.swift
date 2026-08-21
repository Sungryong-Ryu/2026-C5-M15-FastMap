//
//  ContentView.swift
//  FastMap
//
//  Created by RyuHwagodong on 8/12/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var liveActivityController: LiveActivityController
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedPlacesStore: SavedPlacesStore
    @EnvironmentObject private var navigation: WalkingNavigationController
    @EnvironmentObject private var categoryStore: CategoryStore

    var body: some View {
        RadarMapView()
            .task {
                locationService.requestWhenInUseAuthorization()
                await accountManager.validateCredential()
                await store.refreshPlaces(
                    from: locationService.currentLocation,
                    categories: categoryStore.activeCategories
                )
            }
            .task(id: accountManager.account?.userIdentifier) {
                await savedPlacesStore.configure(for: accountManager.account)
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                Task {
                    if navigation.isNavigating {
                        await navigation.updateLocation(newLocation, headingDegrees: locationService.headingDegrees)
                        await updateNavigationLiveActivity()
                    } else {
                        await store.refreshPlaces(
                            from: newLocation,
                            categories: categoryStore.activeCategories
                        )
                        await liveActivityController.update(place: store.selectedPlace, deviceHeadingDegrees: locationService.headingDegrees)
                    }
                }
            }
            .onChange(of: locationService.headingDegrees) { _, newHeading in
                Task {
                    if navigation.isNavigating {
                        await updateNavigationLiveActivity()
                    } else {
                        await liveActivityController.update(place: store.selectedPlace, deviceHeadingDegrees: newHeading)
                    }
                }
            }
            .onChange(of: store.selectedPlace) { _, newPlace in
                Task {
                    if !navigation.isNavigating {
                        await liveActivityController.update(place: newPlace, deviceHeadingDegrees: locationService.headingDegrees)
                    }
                }
            }
    }

    private func updateNavigationLiveActivity() async {
        guard let place = navigation.destination,
              var snapshot = navigation.snapshot else { return }
        snapshot = snapshot.withArrowRotation(
            navigation.arrowRotation(
                deviceHeadingDegrees: locationService.headingDegrees,
                from: locationService.currentLocation
            )
        )
        await liveActivityController.updateNavigation(place: place, snapshot: snapshot)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
            .environmentObject(LiveActivityController())
            .environmentObject(AccountManager())
            .environmentObject(SavedPlacesStore())
            .environmentObject(WalkingNavigationController())
            .environmentObject(CategoryStore.preview)
            .environmentObject(ProfileStore.preview)
    }
}
