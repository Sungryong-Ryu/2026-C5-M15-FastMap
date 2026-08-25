//
//  RootView.swift
//  CoFFMap
//
//  화면은 지도 하나뿐이라, 여기는 위치·경로·Live Activity를 이어 주는 배선만 합니다.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: CafeStore
    @EnvironmentObject private var liveActivityController: LiveActivityController
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedCafeStore: SavedCafeStore
    @EnvironmentObject private var navigation: WalkingNavigationController

    var body: some View {
        CafeMapView()
            .task {
                locationService.requestWhenInUseAuthorization()
                await accountManager.validateCredential()
                await store.refresh(from: locationService.currentLocation)
            }
            .task(id: accountManager.account?.userIdentifier) {
                await savedCafeStore.configure(for: accountManager.account)
            }
            .onChange(of: locationService.currentLocation) { _, newLocation in
                Task {
                    if navigation.isNavigating {
                        await navigation.updateLocation(
                            newLocation,
                            horizontalAccuracy: locationService.horizontalAccuracy
                        )
                        await updateNavigationLiveActivity()
                    } else {
                        await store.refresh(from: newLocation)
                        await liveActivityController.update(
                            cafe: store.selectedCafe,
                            deviceHeadingDegrees: locationService.headingDegrees
                        )
                    }
                }
            }
            .onChange(of: locationService.headingDegrees) { _, newHeading in
                Task {
                    if navigation.isNavigating {
                        await updateNavigationLiveActivity()
                    } else {
                        await liveActivityController.update(
                            cafe: store.selectedCafe,
                            deviceHeadingDegrees: newHeading
                        )
                    }
                }
            }
            .onChange(of: store.selectedCafe) { _, newCafe in
                Task {
                    guard !navigation.isNavigating else { return }
                    await liveActivityController.update(
                        cafe: newCafe,
                        deviceHeadingDegrees: locationService.headingDegrees
                    )
                }
            }
            // 즐겨찾기 저장이 실패하는 경우가 있습니다. Kakao 카페를 Apple 지도에서
            // 못 찾으면 저장을 포기하는데, 조용히 넘어가면 사용자가 눌렀는데 안 눌린 걸로 보입니다.
            .alert(
                "저장하지 못했어요",
                isPresented: Binding(
                    get: { savedCafeStore.saveFailureMessage != nil },
                    set: { if !$0 { savedCafeStore.saveFailureMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) { savedCafeStore.saveFailureMessage = nil }
            } message: {
                Text(savedCafeStore.saveFailureMessage ?? "")
            }
    }

    private func updateNavigationLiveActivity() async {
        guard let cafe = navigation.destination,
              var snapshot = navigation.snapshot else { return }
        snapshot = snapshot.withArrowRotation(
            navigation.arrowRotation(
                deviceHeadingDegrees: locationService.headingDegrees,
                from: locationService.currentLocation
            )
        )
        await liveActivityController.updateNavigation(cafe: cafe, snapshot: snapshot)
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .environmentObject(LocationService.preview)
            .environmentObject(CafeStore.preview)
            .environmentObject(LiveActivityController())
            .environmentObject(AccountManager())
            .environmentObject(SavedCafeStore())
            .environmentObject(WalkingNavigationController())
            .environmentObject(ProfileStore.preview)
    }
}
