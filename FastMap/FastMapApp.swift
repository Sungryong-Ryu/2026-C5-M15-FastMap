//
//  FastMapApp.swift
//  FastMap
//
//  Created by RyuHwagodong on 8/12/26.
//

import SwiftUI

@main
struct FastMapApp: App {
    @StateObject private var locationService = LocationService()
    @StateObject private var store = FastMapStore()
    @StateObject private var liveActivityController = LiveActivityController()
    @StateObject private var accountManager = AccountManager()
    @StateObject private var savedPlacesStore = SavedPlacesStore()
    @StateObject private var walkingNavigationController = WalkingNavigationController()
    @StateObject private var categoryStore = CategoryStore()
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(store)
                .environmentObject(liveActivityController)
                .environmentObject(accountManager)
                .environmentObject(savedPlacesStore)
                .environmentObject(walkingNavigationController)
                .environmentObject(categoryStore)
                .environmentObject(profileStore)
                .tint(TossColor.blue)
                .preferredColorScheme(.dark)
        }
    }
}
