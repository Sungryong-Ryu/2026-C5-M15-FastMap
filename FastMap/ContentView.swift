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

    var body: some View {
        RadarMapView()
            .task {
                locationService.requestWhenInUseAuthorization()
                await store.refreshPlaces(from: locationService.currentLocation)
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                Task {
                    await store.refreshPlaces(from: newLocation)
                    await liveActivityController.update(place: store.selectedPlace, deviceHeadingDegrees: locationService.headingDegrees)
                }
            }
            .onChange(of: locationService.headingDegrees) { _, newHeading in
                Task {
                    await liveActivityController.update(place: store.selectedPlace, deviceHeadingDegrees: newHeading)
                }
            }
            .onChange(of: store.selectedPlace) { _, newPlace in
                Task {
                    await liveActivityController.update(place: newPlace, deviceHeadingDegrees: locationService.headingDegrees)
                }
            }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
            .environmentObject(LiveActivityController())
    }
}
