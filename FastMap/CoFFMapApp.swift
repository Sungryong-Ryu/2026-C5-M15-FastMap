//
//  CoFFMapApp.swift
//  CoFFMap
//
//  카페만 보여 주는 지도 앱.
//

import SwiftUI

@main
struct CoFFMapApp: App {
    @State private var isShowingLaunchSplash = true
    @StateObject private var locationService = LocationService()
    @StateObject private var store = CafeStore()
    @StateObject private var liveActivityController = LiveActivityController()
    @StateObject private var accountManager = AccountManager()
    @StateObject private var savedCafeStore = SavedCafeStore()
    @StateObject private var walkingNavigationController = WalkingNavigationController()
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingLaunchSplash {
                    LaunchSplashView()
                        .transition(.opacity)
                } else {
                    RootView()
                        .transition(.opacity)
                }
            }
            .task {
                await finishLaunchSplashAfterDelay()
            }
            .environmentObject(locationService)
            .environmentObject(store)
            .environmentObject(liveActivityController)
            .environmentObject(accountManager)
            .environmentObject(savedCafeStore)
            .environmentObject(walkingNavigationController)
            .environmentObject(profileStore)
            .tint(TossColor.blue)
            .preferredColorScheme(.dark)
        }
    }

    private func finishLaunchSplashAfterDelay() async {
        guard isShowingLaunchSplash else { return }

        do {
            try await Task.sleep(for: .seconds(2))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.35)) {
            isShowingLaunchSplash = false
        }
    }
}
