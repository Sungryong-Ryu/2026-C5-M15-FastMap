//
//  CafeMapView.swift
//  WhereismyAHAH
//
//  앱의 유일한 화면. 지도가 배경이고, 하단 시트에서 검색하고 고릅니다.
//
//  지도 위 UI는 그 자체가 가려지는 지도 면적입니다. 그래서 거리 칩을 길게 늘어놓지 않고
//  현재 조건만 보여 주는 작은 필터 버튼 하나로 줄였습니다. 거리와 유형 선택은 시트가 맡습니다.
//
//  시트 동작은 예전 구조를 그대로 지켰습니다 — 지도 컨트롤·칩·카드를 한 컨테이너에 넣고
//  한 번의 offset으로 같이 움직입니다. 드래그 중에 Map이 다시 그려지면 움직임이 떨려서,
//  카드 위치를 부모로 되돌려 보내지 않는 게 핵심입니다. 암시적 애니메이션도 붙이지 않습니다.
//

import MapKit
import SwiftUI

struct CafeMapView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: CafeStore
    @EnvironmentObject private var liveActivityController: LiveActivityController
    @EnvironmentObject private var navigation: WalkingNavigationController
    @Namespace private var mapScope

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .seoulCityHall,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    /// 지금 화면에 보이는 지도 영역. "이 지역 검색"이 훑을 범위입니다.
    @State private var visibleRegion = MKCoordinateRegion(
        center: .seoulCityHall,
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
    )
    @State private var isShowingAccount = false
    @State private var isShowingNavigation = false
    @State private var isDrawerExpanded = ProcessInfo.processInfo.arguments.contains("-ui-test-expanded-drawer")
    @State private var mapHeading = 0.0
    /// 실제 GPS 위치를 받아 카메라를 맞춘 적이 있는지. 앱을 켤 때 한 번만 필요합니다.
    @State private var hasCenteredOnUserLocation = false

    var body: some View {
        ZStack(alignment: .bottom) {
            map
            bottomOverlay
        }
        .sheet(isPresented: $isShowingAccount) {
            AccountCenterView()
                .presentationDetents([.large])
                .presentationCornerRadius(TossRadius.sheet)
        }
        .fullScreenCover(isPresented: $isShowingNavigation) {
            WalkingNavigationView()
        }
        .onAppear { focusUserLocation() }
        // 앱을 켠 직후에는 아직 GPS 값이 없어 임시 좌표가 들어 있습니다.
        // 실제 위치가 처음 잡히는 순간 카메라를 현위치로 맞추고 주변을 다시 검색합니다.
        .onChange(of: locationService.isUsingFallbackLocation) { _, isUsingFallback in
            guard !isUsingFallback, !hasCenteredOnUserLocation else { return }
            hasCenteredOnUserLocation = true

            withAnimation(TossMotion.snappy) { focusUserLocation() }
            Task { await store.refresh(from: locationService.currentLocation, force: true) }
        }
        .onChange(of: store.selectedCafe) { _, newCafe in
            guard let newCafe else { return }
            withAnimation(TossMotion.snappy) { focusCamera(on: newCafe.coordinate) }
            Task { await store.updateRoute(from: locationService.currentLocation) }
        }
        // 거리 "전체"로 지역이 정해지면 그 구역이 다 보이도록 물러섭니다.
        // 지도로 옮겨 간 지역은 사용자가 이미 화면을 잡아 둔 상태라 건드리지 않습니다.
        .onChange(of: store.scope) { _, newScope in
            guard case .region(let region) = newScope else { return }
            withAnimation(TossMotion.snappy) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: region.center,
                        latitudinalMeters: region.radiusMeters * 2.4,
                        longitudinalMeters: region.radiusMeters * 2.4
                    )
                )
            }
        }
        .mapScope(mapScope)
    }

    // MARK: - 지도

    private var map: some View {
        Map(position: $cameraPosition, selection: mapSelection, scope: mapScope) {
            UserAnnotation()

            ForEach(store.mapCafes) { cafe in
                Marker(cafe.name, systemImage: markerSymbol(for: cafe), coordinate: cafe.coordinate)
                    .tint(markerTint(for: cafe))
                    .tag(cafe)
            }

            // 검색으로 고르거나, 마커 상한에 걸려 잘려 나간 카페는 따로 찍어 줍니다.
            if let selectedCafe = store.selectedCafe, !store.mapCafes.contains(selectedCafe) {
                Marker(selectedCafe.name, systemImage: markerSymbol(for: selectedCafe), coordinate: selectedCafe.coordinate)
                    .tint(markerTint(for: selectedCafe))
                    .tag(selectedCafe)
            }

            if let route = store.route {
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue.opacity(0.22), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        // 카페만 보여 주는 앱이니 Apple의 기본 POI 아이콘도 카페만 남깁니다.
        // 이게 없으면 우리 마커와 애플의 편의점·음식점 아이콘이 뒤섞여 지도가 지저분해집니다.
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .including([.cafe])))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        // 영역은 카메라가 멈춘 뒤에만 받습니다. 매 프레임 갱신하면 시트를 끌 때 같이 떨립니다.
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .ignoresSafeArea()
    }

    /// 마커 아이콘은 가장 앞선 태그를 따릅니다. 태그가 없으면 그냥 커피잔입니다.
    private func markerSymbol(for cafe: Cafe) -> String {
        cafe.orderedTags.first?.symbolName ?? "cup.and.saucer.fill"
    }

    private func markerTint(for cafe: Cafe) -> Color {
        cafe.orderedTags.first?.tint ?? TossCategoryColor.brown
    }

    private var mapSelection: Binding<Cafe?> {
        Binding(
            get: { store.selectedCafe },
            set: { cafe in
                store.selectedCafe = cafe
                if cafe != nil {
                    withAnimation(TossMotion.snappy) { isDrawerExpanded = true }
                }
            }
        )
    }

    private var bottomOverlay: some View {
        CafeDrawer(
            isExpanded: $isDrawerExpanded,
            mapScope: mapScope,
            isMapRotated: isMapRotated,
            isMapAwayFromResults: isMapAwayFromResults,
            showAccount: { isShowingAccount = true },
            focusUserLocation: {
                resumeMapLocationUpdates()
                withAnimation(TossMotion.snappy) { focusUserLocation() }
                // 다른 지역을 보다가 현위치 버튼을 누르면 목록도 같이 내 주변으로 돌아옵니다.
                // 카메라만 돌아오고 목록은 속초에 남아 있으면 화면과 목록이 어긋납니다.
                if store.isBrowsingElsewhere {
                    Task { await store.returnToNearby(around: locationService.currentLocation) }
                }
            },
            searchVisibleArea: {
                Task {
                    await store.searchVisibleArea(
                        center: visibleRegion.center,
                        radiusMeters: visibleRadiusMeters,
                        userLocation: locationService.currentLocation
                    )
                }
            },
            startNavigation: { cafe, mode in
                Task { await startNavigation(to: cafe, mode: mode) }
            }
        )
    }

    private var isMapRotated: Bool {
        let normalizedHeading = mapHeading.truncatingRemainder(dividingBy: 360)
        let distanceFromNorth = min(normalizedHeading, 360 - normalizedHeading)
        return distanceFromNorth > 0.5
    }

    /// 화면 절반을 미터로 환산한 값. "이 지역 검색"이 훑을 반경입니다.
    private var visibleRadiusMeters: CLLocationDistance {
        let metersPerDegree = 111_000.0
        let latitudeMeters = visibleRegion.span.latitudeDelta * metersPerDegree
        let longitudeMeters = visibleRegion.span.longitudeDelta * metersPerDegree
            * cos(visibleRegion.center.latitude * .pi / 180)
        return max(latitudeMeters, longitudeMeters) / 2
    }

    /// 지금 보고 있는 지도가 목록을 만든 지역에서 벗어났는지.
    /// 벗어났으면 "이 지역 검색" 버튼을 눈에 띄게 바꿉니다.
    private var isMapAwayFromResults: Bool {
        let drift = GeoMath.distanceMeters(from: visibleRegion.center, to: store.searchOrigin)
        return drift > max(visibleRadiusMeters, 500)
    }

    private func focusCamera(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .camera(
            MapCamera(centerCoordinate: coordinate, distance: 900, heading: 0, pitch: 0)
        )
    }

    private func focusUserLocation() {
        cameraPosition = .userLocation(
            followsHeading: false,
            fallback: .region(
                MKCoordinateRegion(
                    center: locationService.currentLocation,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
            )
        )
    }

    private func startNavigation(to cafe: Cafe, mode: NavigationMode) async {
        locationService.startNavigationUpdates(for: mode)
        await navigation.start(
            to: cafe,
            from: locationService.currentLocation,
            mode: mode
        )

        guard navigation.isNavigating else {
            resumeMapLocationUpdates()
            return
        }

        await liveActivityController.startTracking(
            cafe: cafe,
            deviceHeadingDegrees: locationService.headingDegrees
        )
        if var snapshot = navigation.snapshot {
            snapshot = snapshot.withArrowRotation(
                navigation.arrowRotation(
                    deviceHeadingDegrees: locationService.headingDegrees,
                    from: locationService.currentLocation
                )
            )
            await liveActivityController.updateNavigation(cafe: cafe, snapshot: snapshot)
        }
        isShowingNavigation = true
    }

    private func resumeMapLocationUpdates() {
        syncLocationAccuracy(locationService, store)
    }
}

/// 거리 필터에 맞춰 위치 갱신 정밀도를 맞춥니다.
///
/// 50~500m처럼 촘촘한 거리를 켰을 때만 정밀 GPS가 필요합니다. 그보다 넓은 범위에서
/// 정밀 갱신을 켜 두면 배터리만 깎입니다.
private func syncLocationAccuracy(_ locationService: LocationService, _ store: CafeStore) {
    if store.needsPreciseLocation {
        locationService.startProximityUpdates()
    } else {
        locationService.startEfficientUpdates()
    }
}

// MARK: - 하단 시트

private struct CafeDrawer: View {
    @Binding var isExpanded: Bool
    let mapScope: Namespace.ID
    let isMapRotated: Bool
    let isMapAwayFromResults: Bool
    let showAccount: () -> Void
    let focusUserLocation: () -> Void
    let searchVisibleArea: () -> Void
    let startNavigation: (Cafe, NavigationMode) -> Void

    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: CafeStore
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedCafeStore: SavedCafeStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var searchQuery = ""
    @State private var searchResults: [Cafe] = []
    @State private var isSearching = false
    @State private var selectedNavigationMode: NavigationMode = .walking
    @State private var isShowingFilters = false

    /// 카드 전체 높이와, 접었을 때 보이는 머리 부분 높이.
    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// 드래그를 시작한 순간의 offset. nil이면 드래그 중이 아닙니다.
    @State private var dragAnchor: CGFloat?
    /// 드래그 시작 지점을 기준으로 한 이동량.
    @State private var dragDelta: CGFloat = 0
    /// 제스처가 인식된 순간의 translation. 시작할 때 카드가 튀지 않게 보정합니다.
    @State private var startTranslation: CGFloat = 0

    private var isDragging: Bool { dragAnchor != nil }

    /// 접었을 때 화면 아래로 감춰지는 양.
    private var hiddenAmount: CGFloat { max(0, contentHeight - headerHeight) }

    /// 카드를 아래로 밀어 둔 정도. 0이면 완전히 펼쳐진 상태입니다.
    private var offsetY: CGFloat {
        let base = dragAnchor ?? (isExpanded ? 0 : hiddenAmount)
        return min(hiddenAmount, max(0, base + dragDelta))
    }

    private var progress: CGFloat {
        hiddenAmount <= 0 ? 0 : 1 - offsetY / hiddenAmount
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: TossSpacing.s) {
            floatingToolbar

            card
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheet(isPresented: $isShowingFilters) {
            CafeFilterSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(TossRadius.sheet)
        }
        // 암시적 애니메이션 금지. 드래그 중에는 손가락을 그대로 따라가야 하고,
        // 놓을 때만 withAnimation으로 붙입니다.
        .offset(y: offsetY)
    }

    // MARK: 지도 위 요소

    private var mapControls: some View {
        VStack(spacing: TossSpacing.s) {
            if isMapRotated {
                MapCompass(scope: mapScope)
                    .mapControlVisibility(.visible)
                    .accessibilityLabel("지도를 북쪽 방향으로 돌리기")
            }

            TossFloatingCircleButton(systemName: "location.fill", label: "현재 위치로 이동") {
                focusUserLocation()
            }

            // 지도를 옮겨 놓고 누르면 그 지역의 카페를 찾습니다.
            // 화면이 아직 내 위치 근처면 예전처럼 주변을 새로고침합니다.
            TossFloatingCircleButton(
                systemName: "arrow.clockwise",
                label: "지도에 보이는 지역의 카페 검색",
                showsProgress: store.isLoading,
                tint: isMapAwayFromResults ? TossColor.blue : nil
            ) {
                searchVisibleArea()
            }
        }
        .animation(TossMotion.quick, value: isMapRotated)
    }

    // MARK: 컴팩트 필터

    /// 지도 컨트롤은 필터 행의 오른쪽 위로 겹쳐 올립니다. 오버레이는 레이아웃 높이를
    /// 늘리지 않으므로, 예전의 긴 거리 바만큼 지도를 가리지 않습니다.
    private var floatingToolbar: some View {
        filterButton
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                mapControls
                    .opacity(1 - progress)
                    .allowsHitTesting(progress < 0.4)
            }
            .padding(.horizontal, TossEdge.floatingInset)
    }

    private var filterButton: some View {
        let count = store.activeTags.count

        return Button {
            searchQuery = ""
            searchResults = []
            isShowingFilters = true
        } label: {
            HStack(spacing: TossSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .bold))

                Text(activeDistanceTitle)
                    .font(.system(size: 13, weight: .semibold))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TossColor.textOnBlue)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(MusicGradient.accent, in: Circle())
                }

                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TossColor.textTertiary)
            }
            .foregroundStyle(TossColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: TossSize.compactChipHeight)
            .background {
                Capsule()
                    .fill(TossColor.floatingSurface)
                    .overlay { Capsule().strokeBorder(TossColor.line, lineWidth: 1) }
                    .tossShadow(.floating)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityLabel("카페 필터, 거리 \(activeDistanceTitle), 유형 \(count)개 선택됨")
    }

    private var activeDistanceTitle: String {
        store.activeRadiusMeters.map(CafeStore.distanceLabel) ?? "전체"
    }

    // MARK: 카드

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            expandedBlock
        }
        .contentShape(Rectangle())
        .tossSheetSurface()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            // 드래그 도중에 높이가 바뀌면 카드가 튑니다. 손을 뗀 뒤에만 반영합니다.
            guard !isDragging, abs(height - contentHeight) > 0.5 else { return }
            contentHeight = height
        }
    }

    /// 접었을 때도 항상 보이는 부분. 여기를 잡고 끌어올리면 카드가 손가락을 따라 자랍니다.
    private var header: some View {
        VStack(alignment: .leading, spacing: TossSpacing.s) {
            drawerHandle
            searchBar
        }
        .padding(.horizontal, TossEdge.screenInset)
        .padding(.top, TossSpacing.xs)
        .padding(.bottom, TossSpacing.m)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            guard !isDragging, abs(height - headerHeight) > 0.5 else { return }
            headerHeight = height
        }
        .simultaneousGesture(dragGesture)
    }

    private var expandedBlock: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            dataSourceNotice
            expandedContent
            navigationControls
        }
        .padding(.horizontal, TossEdge.screenInset)
        .padding(.bottom, TossEdge.bottomInset)
        // 접힌 상태에서는 화면 밖이라 조작을 막습니다.
        .allowsHitTesting(isExpanded)
    }

    /// 손가락을 그대로 따라가는 드래그. 놓으면 가까운 쪽으로 붙습니다.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragAnchor == nil {
                    // 제스처가 인식되는 순간 이미 몇 pt 움직여 있습니다.
                    // 그 값을 기준점으로 삼아야 카드가 손가락을 따라 부드럽게 시작합니다.
                    dragAnchor = isExpanded ? 0 : hiddenAmount
                    dragDelta = 0
                    startTranslation = value.translation.height
                }
                dragDelta = value.translation.height - startTranslation
            }
            .onEnded { value in
                let flick = value.predictedEndTranslation.height - value.translation.height
                let projected = offsetY + flick
                let shouldExpand = projected < hiddenAmount / 2

                withAnimation(TossMotion.snappy) {
                    dragAnchor = nil
                    dragDelta = 0
                    startTranslation = 0
                    isExpanded = shouldExpand
                }
            }
    }

    private var drawerHandle: some View {
        Button {
            withAnimation(TossMotion.snappy) { isExpanded.toggle() }
        } label: {
            TossSheetHandle()
                .frame(maxWidth: .infinity, minHeight: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "카페 목록 접기" : "카페 목록 펼치기")
    }

    // MARK: 검색

    private var searchBar: some View {
        HStack(spacing: TossSpacing.s) {
            HStack(spacing: TossSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)

                TextField("어떤 카페를 찾으세요?", text: $searchQuery)
                    .font(TossFont.body)
                    .foregroundStyle(TossColor.textPrimary)
                    .tint(TossColor.blue)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onTapGesture {
                        withAnimation(TossMotion.snappy) { isExpanded = true }
                    }
                    .onSubmit {
                        Task { await runSearch() }
                    }

                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TossColor.textTertiary)
                } else if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(TossColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, TossSpacing.l)
            .frame(height: TossSize.fieldHeight)
            .background {
                RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                            .fill(TossColor.surfaceAlt.opacity(0.76))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
                    }
            }

            // 계정 버튼은 사용자가 설정한 프로필을 그대로 보여 줍니다.
            Button(action: showAccount) {
                ProfileAvatarView(
                    profile: profileStore.profile,
                    photo: profileStore.photo,
                    size: TossSize.fieldHeight
                )
                .contentShape(Circle())
            }
            .buttonStyle(TossScaleButtonStyle())
            .accessibilityLabel(accountManager.isSignedIn ? "내 계정" : "프로필과 계정")
        }
    }

    private func runSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        // 다른 지역을 보는 중이면 그 지역에서 찾습니다. 속초를 보면서 검색했는데
        // 포항 결과가 나오면 화면과 목록이 어긋납니다.
        searchResults = await store.search(query: query, around: store.searchOrigin)
        if let firstResult = searchResults.first {
            await store.select(firstResult, from: locationService.currentLocation)
        }
    }

    // MARK: 목록

    /// 국내 Kakao / 해외 Apple MapKit 자동 전환 상태를 한 줄로 알려 줍니다.
    @ViewBuilder
    private var dataSourceNotice: some View {
        if let notice = store.dataSource.noticeText {
            HStack(spacing: TossSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(notice)
                    .font(TossFont.footnote)
                    .lineLimit(2)
            }
            .foregroundStyle(store.dataSource.isWarning ? TossColor.yellow : TossColor.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TossSpacing.m)
            .padding(.vertical, TossSpacing.s)
            .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isSearching {
            loadingState("카페를 찾고 있어요")
        } else if !searchResults.isEmpty {
            if visibleSearchResults.isEmpty {
                TossEmptyState(
                    systemImage: "scope",
                    title: "선택한 거리 안에 검색 결과가 없어요",
                    message: "거리 범위를 넓혀 보세요."
                )
                .frame(minHeight: 170)
            } else {
                cafeList(
                    visibleSearchResults,
                    title: "검색 결과",
                    detail: "\(visibleSearchResults.count)곳"
                )
            }
        } else if store.isLoading {
            loadingState(loadingTitle)
        } else if store.cafes.isEmpty {
            TossEmptyState(
                systemImage: "cup.and.saucer",
                title: emptyTitle,
                message: emptyMessage
            )
            .frame(minHeight: 170)
        } else {
            cafeList(
                store.cafes,
                title: store.scopeTitle,
                detail: store.scopeDetail(count: store.cafes.count)
            )
        }
    }

    private var visibleSearchResults: [Cafe] {
        searchResults
            .map { $0.relative(to: store.searchOrigin) }
            .filter(store.isWithinActiveRadius)
    }

    private var loadingTitle: String {
        guard store.activeRadiusMeters == nil else { return "카페를 찾고 있어요" }
        return store.isBrowsingElsewhere
            ? "지도에 보이는 지역을 훑고 있어요"
            : "지역 전체를 훑고 있어요"
    }

    private var emptyTitle: String {
        store.hasActiveFilters ? "조건에 맞는 카페가 없어요" : "주변에 카페가 없어요"
    }

    private var emptyMessage: String {
        if let radius = store.activeRadiusMeters {
            return "\(CafeStore.distanceLabel(radius))보다 넓은 거리로 바꿔 보세요."
        }
        return store.activeTags.isEmpty
            ? "잠시 후 다시 시도해 주세요."
            : "태그를 하나 꺼 보면 더 많이 나와요."
    }

    private func loadingState(_ title: String) -> some View {
        VStack(spacing: TossSpacing.m) {
            ProgressView()
                .tint(TossColor.blue)
            Text(title)
                .font(TossFont.callout)
                .foregroundStyle(TossColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private func cafeList(_ cafes: [Cafe], title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: TossSpacing.s) {
            listHeader(title: title, detail: detail)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(cafes) { cafe in
                        HStack(spacing: 0) {
                            Button {
                                searchQuery = searchResults.isEmpty ? searchQuery : cafe.name
                                Task { await store.select(cafe, from: locationService.currentLocation) }
                            } label: {
                                CafeRow(cafe: cafe, isSelected: cafe == store.selectedCafe)
                            }
                            .buttonStyle(TossPressableStyle(cornerRadius: TossRadius.field))
                            .accessibilityLabel("\(cafe.name), \(GeoMath.formattedDistance(cafe.distanceMeters))")
                            .accessibilityValue(cafe == store.selectedCafe ? "선택됨" : "")

                            BookmarkButton(isSaved: savedCafeStore.contains(cafe)) {
                                toggleSaved(cafe)
                            }
                        }

                        if cafe.id != cafes.last?.id {
                            TossDivider(leadingInset: 56)
                        }
                    }
                }
            }
            .frame(maxHeight: 292)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 목록 제목 줄. 다른 지역을 보는 중이면 여기로 되돌아올 길을 같이 둡니다.
    private func listHeader(title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TossSpacing.s) {
            Text(title)
                .font(TossFont.title3)
                .foregroundStyle(TossColor.textPrimary)
                .lineLimit(1)

            if store.isBrowsingElsewhere {
                Button {
                    Task { await store.returnToNearby(around: locationService.currentLocation) }
                } label: {
                    Text("내 주변으로")
                        .font(TossFont.footnote)
                        .foregroundStyle(TossColor.blue)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: TossSpacing.s)

            Text(detail)
                .font(TossFont.caption)
                .foregroundStyle(TossColor.textTertiary)
                .lineLimit(1)
        }
    }

    // MARK: 선택한 카페

    /// 다른 지역을 구경하다 고른 카페는 걸어갈 수 있는 거리가 아닐 수 있습니다.
    private var isSelectionTooFar: Bool {
        guard let selectedCafe = store.selectedCafe else { return false }
        return GeoMath.distanceMeters(
            from: locationService.currentLocation,
            to: selectedCafe.coordinate
        ) > CafeStore.walkableLimitMeters
    }

    @ViewBuilder
    private var navigationControls: some View {
        if let selectedCafe = store.selectedCafe {
            VStack(spacing: TossSpacing.m) {
                TossDivider()

                HStack(alignment: .top, spacing: TossSpacing.m) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedCafe.name)
                            .font(TossFont.title2)
                            .foregroundStyle(TossColor.textPrimary)
                            .lineLimit(1)

                        Text(routeSummary(for: selectedNavigationMode, cafe: selectedCafe))
                            .font(TossFont.callout)
                            .foregroundStyle(TossColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: TossSpacing.xxs)

                    BookmarkButton(isSaved: savedCafeStore.contains(selectedCafe)) {
                        toggleSaved(selectedCafe)
                    }
                }

                if !isSelectionTooFar {
                    navigationModePicker
                }

                HStack(spacing: TossSpacing.s) {
                    // 카카오맵 상세 페이지가 있으면 그쪽이 리뷰·사진까지 볼 수 있어 낫습니다.
                    if let placeURL = selectedCafe.placeURL {
                        Link(destination: placeURL) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(TossColor.textPrimary)
                                .frame(width: TossSize.ctaHeight, height: TossSize.ctaHeight)
                                .background(
                                    TossColor.surfaceAlt,
                                    in: RoundedRectangle(cornerRadius: TossRadius.button, style: .continuous)
                                )
                        }
                        .accessibilityLabel("카카오맵에서 자세히 보기")
                    } else {
                        Button {
                            openWalkingDirections(to: selectedCafe)
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .buttonStyle(TossSecondaryButtonStyle())
                        .frame(width: TossSize.ctaHeight)
                        .accessibilityLabel("Apple 지도로 길안내")
                    }

                    Button {
                        startNavigation(selectedCafe, selectedNavigationMode)
                    } label: {
                        Text(isSelectionTooFar ? "여기서는 길안내를 시작할 수 없어요" : "\(selectedNavigationMode.title) 길안내 시작")
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .buttonStyle(TossPrimaryButtonStyle())
                    .disabled(isSelectionTooFar)
                }
            }
        }
    }

    private var navigationModePicker: some View {
        HStack(spacing: TossSpacing.s) {
            ForEach(NavigationMode.allCases) { mode in
                Button {
                    withAnimation(TossMotion.quick) { selectedNavigationMode = mode }
                } label: {
                    VStack(spacing: TossSpacing.xs) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(mode.title)
                            .font(TossFont.footnote)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedNavigationMode == mode ? TossColor.blue : TossColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(
                        selectedNavigationMode == mode ? TossColor.blueWeak : TossColor.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                    )
                }
                .buttonStyle(TossScaleButtonStyle())
                .accessibilityLabel("\(mode.title) 길찾기")
                .accessibilityAddTraits(selectedNavigationMode == mode ? .isSelected : [])
            }
        }
    }

    private func routeSummary(for mode: NavigationMode, cafe: Cafe) -> String {
        if isSelectionTooFar {
            let distance = GeoMath.distanceMeters(
                from: locationService.currentLocation,
                to: cafe.coordinate
            )
            return "내 위치에서 \(GeoMath.formattedDistance(distance)) · 둘러보기만 돼요"
        }
        guard mode == .walking, let route = store.route else {
            return "\(mode.title) · Kakao 경로로 안내"
        }
        let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
        return "도보 약 \(minutes)분 · \(GeoMath.formattedDistance(route.distance))"
    }

    private func openWalkingDirections(to cafe: Cafe) {
        cafe.mapItem.openInMaps(
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]
        )
    }

    private func toggleSaved(_ cafe: Cafe) {
        guard accountManager.isSignedIn else {
            showAccount()
            return
        }
        Task { await savedCafeStore.toggle(cafe) }
    }
}

// MARK: - 카페 필터

private struct CafeFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: CafeStore

    @State private var shouldRefreshTagSearch = false

    private let distanceColumns = Array(repeating: GridItem(.flexible(), spacing: TossSpacing.s), count: 3)
    private let tagColumns = Array(repeating: GridItem(.flexible(), spacing: TossSpacing.s), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TossSpacing.xxl) {
                    distanceSection
                    tagSection
                }
                .padding(.horizontal, TossEdge.screenInset)
                .padding(.top, TossSpacing.l)
                .padding(.bottom, TossSpacing.xxl)
            }
            .scrollIndicators(.hidden)
            .tossPageBackground()
            .safeAreaInset(edge: .bottom) {
                Button("필터 적용") { dismiss() }
                    .buttonStyle(TossPrimaryButtonStyle())
                    .padding(.horizontal, TossEdge.screenInset)
                    .padding(.vertical, TossSpacing.m)
                    .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("카페 필터")
                        .font(TossFont.title3)
                        .foregroundStyle(TossColor.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("초기화") { resetFilters() }
                        .font(TossFont.callout)
                        .foregroundStyle(store.hasActiveFilters ? TossColor.blue : TossColor.textTertiary)
                        .disabled(!store.hasActiveFilters)
                }
            }
            .toolbarBackground(TossColor.background.opacity(0.88), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        }
        .onDisappear {
            guard shouldRefreshTagSearch else { return }
            Task {
                await store.refresh(from: locationService.currentLocation, force: true)
            }
        }
    }

    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            filterSectionHeader(title: "거리", subtitle: distanceSubtitle)

            LazyVGrid(columns: distanceColumns, spacing: TossSpacing.s) {
                ForEach(CafeStore.distanceOptions, id: \.self) { radius in
                    distanceButton(title: CafeStore.distanceLabel(radius), radius: radius)
                }
                distanceButton(title: "전체", radius: nil)
            }
        }
    }

    private var distanceSubtitle: String {
        if let radius = store.activeRadiusMeters {
            return store.isBrowsingElsewhere
                ? "이 지역 중심에서 \(CafeStore.distanceLabel(radius)) 안"
                : "현 위치에서 \(CafeStore.distanceLabel(radius)) 안"
        }
        switch store.scope {
        case .region(let region): return "\(region.fullTitle) 전체"
        case .mapArea: return "지도에 보이는 지역 전체"
        case .nearby: return "지금 있는 지역 전체"
        }
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
            filterSectionHeader(
                title: "카페 유형",
                subtitle: store.activeTags.isEmpty ? "모든 유형" : "\(store.activeTags.count)개 선택"
            )

            LazyVGrid(columns: tagColumns, spacing: TossSpacing.s) {
                ForEach(CafeTag.displayOrder) { tag in
                    tagButton(tag)
                }
            }

            Label("여러 유형을 고르면 모든 조건에 맞는 카페만 보여줘요.", systemImage: "info.circle")
                .font(TossFont.footnote)
                .foregroundStyle(TossColor.textSecondary)
                .padding(.horizontal, TossSpacing.m)
                .padding(.vertical, TossSpacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TossColor.background.opacity(0.72), in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                }
        }
    }

    private func filterSectionHeader(title: String, subtitle: String) -> some View {
        TossSectionHeader(title: title, trailing: subtitle)
    }

    private func distanceButton(title: String, radius: Int?) -> some View {
        let isSelected = store.isActive(radiusMeters: radius)

        return Button {
            Task {
                await store.setRadius(radius, around: locationService.currentLocation)
                syncLocationAccuracy(locationService, store)
            }
        } label: {
            VStack(spacing: TossSpacing.xs) {
                Image(systemName: radius == nil ? "square.dashed" : "scope")
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(TossFont.footnote)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? TossColor.textOnBlue : TossColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                isSelected ? AnyShapeStyle(MusicGradient.accent) : AnyShapeStyle(TossColor.surfaceAlt),
                in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
            )
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tagButton(_ tag: CafeTag) -> some View {
        let isSelected = store.isActive(tag)

        return Button {
            store.toggle(tag)
            shouldRefreshTagSearch = true
        } label: {
            VStack(alignment: .leading, spacing: TossSpacing.s) {
                HStack {
                    Image(systemName: tag.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tag.tint)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tag.tint)
                    }
                }

                Text(tag.title)
                    .font(TossFont.footnote)
                    .foregroundStyle(isSelected ? TossColor.textPrimary : TossColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(TossSpacing.m)
            .background(
                isSelected ? tag.tint.opacity(0.16) : TossColor.surfaceAlt,
                in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                    .stroke(isSelected ? tag.tint.opacity(0.7) : TossColor.line, lineWidth: 1)
            }
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func resetFilters() {
        if !store.activeTags.isEmpty { shouldRefreshTagSearch = true }
        store.clearTags()
        Task {
            await store.setRadius(CafeStore.defaultRadiusMeters, around: locationService.currentLocation)
            syncLocationAccuracy(locationService, store)
        }
    }
}

// MARK: - 조각

private struct BookmarkButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSaved ? TossColor.blue : TossColor.textTertiary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityLabel(isSaved ? "저장 취소" : "카페 저장")
    }
}

private struct CafeRow: View {
    let cafe: Cafe
    let isSelected: Bool

    /// 한 줄에 다 안 들어가서 앞의 두 개만 보여 줍니다.
    private var visibleTags: [CafeTag] { Array(cafe.orderedTags.prefix(2)) }

    var body: some View {
        HStack(spacing: TossSpacing.m) {
            TossIconBadge(
                systemName: cafe.orderedTags.first?.symbolName ?? "cup.and.saucer.fill",
                tint: cafe.orderedTags.first?.tint ?? TossCategoryColor.brown,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(cafe.name)
                    .font(TossFont.headline)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)

                if visibleTags.isEmpty {
                    Text(cafe.displayAddress)
                        .font(TossFont.caption)
                        .foregroundStyle(TossColor.textSecondary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        ForEach(visibleTags) { tag in
                            Text(tag.title)
                                .font(TossFont.footnote)
                                .foregroundStyle(tag.tint)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(tag.tint.opacity(0.14), in: Capsule())
                        }
                        Text(cafe.displayAddress)
                            .font(TossFont.caption)
                            .foregroundStyle(TossColor.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(GeoMath.formattedDistance(cafe.distanceMeters))
                    .font(TossFont.bodyStrong)
                    .foregroundStyle(isSelected ? TossColor.blue : TossColor.textPrimary)
                Text(GeoMath.directionText(for: cafe.bearingDegrees))
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, TossSpacing.m)
        .padding(.horizontal, TossSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(MusicGradient.softAccent) : AnyShapeStyle(.clear))
        )
    }
}

struct CafeMapView_Previews: PreviewProvider {
    static var previews: some View {
        CafeMapView()
            .environmentObject(LocationService.preview)
            .environmentObject(CafeStore.preview)
            .environmentObject(LiveActivityController())
            .environmentObject(AccountManager())
            .environmentObject(SavedCafeStore())
            .environmentObject(WalkingNavigationController())
            .environmentObject(ProfileStore.preview)
    }
}
