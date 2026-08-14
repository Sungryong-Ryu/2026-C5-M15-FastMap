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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationService)
                .environmentObject(store)
                .environmentObject(liveActivityController)
        }
    }
}
