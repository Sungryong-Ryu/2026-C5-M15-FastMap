import MapKit
import SwiftUI

struct RadarMapView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var liveActivityController: LiveActivityController
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedPlacesStore: SavedPlacesStore
    @EnvironmentObject private var navigation: WalkingNavigationController
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var profileStore: ProfileStore
    @Namespace private var mapScope

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .seoulCityHall,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    @State private var presentedSheet: PresentedSheet?
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .settings:
                CategorySettingsView()
                    .environmentObject(categoryStore)
                    .presentationDetents([.large])
                    .presentationCornerRadius(TossRadius.sheet)
            case .account:
                AccountCenterView()
                    .environmentObject(profileStore)
                    .presentationDetents([.large])
                    .presentationCornerRadius(TossRadius.sheet)
            }
        }
        .fullScreenCover(isPresented: $isShowingNavigation) {
            WalkingNavigationView()
        }
        .onAppear {
            focusUserLocation()
        }
        // 앱을 켠 직후에는 아직 GPS 값이 없어 임시 좌표가 들어 있습니다.
        // 실제 위치가 처음 잡히는 순간 카메라를 현위치로 맞추고 주변을 다시 검색합니다.
        .onChange(of: locationService.isUsingFallbackLocation) { _, isUsingFallback in
            guard !isUsingFallback, !hasCenteredOnUserLocation else { return }
            hasCenteredOnUserLocation = true

            withAnimation(TossMotion.snappy) {
                focusUserLocation()
            }
            Task {
                await store.refreshPlaces(
                    from: locationService.currentLocation,
                    categories: categoryStore.activeCategories,
                    force: true
                )
            }
        }
        .onChange(of: store.selectedPlace) { _, newPlace in
            if let newPlace {
                withAnimation(TossMotion.snappy) {
                    focusCamera(on: newPlace.coordinate)
                }
                Task {
                    await store.updateRoute(from: locationService.currentLocation)
                }
            }
        }
        .mapScope(mapScope)
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: mapSelection, scope: mapScope) {
            UserAnnotation()

            ForEach(store.places) { place in
                Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate)
                    .tint(place.category.tint)
                    .tag(place)
            }

            if let selectedPlace = store.selectedPlace, !store.places.contains(selectedPlace) {
                Marker(
                    selectedPlace.name,
                    systemImage: selectedPlace.category.symbolName,
                    coordinate: selectedPlace.coordinate
                )
                .tint(selectedPlace.category.tint)
                .tag(selectedPlace)
            }

            if let route = store.route {
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue.opacity(0.22), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                MapPolyline(route.polyline)
                    .stroke(TossColor.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: pointOfInterestFilter))
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in
            mapHeading = context.camera.heading
        }
        .ignoresSafeArea()
    }

    private var mapSelection: Binding<Place?> {
        Binding(
            get: { store.selectedPlace },
            set: { place in
                store.selectedPlace = place
                if place != nil {
                    withAnimation(TossMotion.snappy) {
                        isDrawerExpanded = true
                    }
                }
            }
        )
    }

    /// 하단 레이어 전체를 PlaceDrawer 하나에 맡깁니다.
    ///
    /// 드래그 중에 이 뷰(그리고 Map)가 매 프레임 다시 그려지면 애니메이션이 떨립니다.
    /// 그래서 카드 위치·진행도를 부모로 되돌려 보내지 않고, 지도 컨트롤과 카테고리 칩까지
    /// 카드와 같은 컨테이너에 넣어 한 번의 offset으로 함께 움직이게 했습니다.
    private var bottomOverlay: some View {
        PlaceDrawer(
            isExpanded: $isDrawerExpanded,
            mapScope: mapScope,
            isMapRotated: isMapRotated,
            showAccount: { presentedSheet = .account },
            showSettings: { presentedSheet = .settings },
            focusUserLocation: {
                locationService.startEfficientUpdates()
                withAnimation(TossMotion.snappy) {
                    focusUserLocation()
                }
            },
            startNavigation: { place in
                Task { await startNavigation(to: place) }
            }
        )
    }

    private var isMapRotated: Bool {
        let normalizedHeading = mapHeading.truncatingRemainder(dividingBy: 360)
        let distanceFromNorth = min(normalizedHeading, 360 - normalizedHeading)
        return distanceFromNorth > 0.5
    }

    private var pointOfInterestFilter: PointOfInterestCategories {
        let categories = categoryStore.activeCategories.flatMap { category in
            category.pointOfInterestCategories ?? []
        }

        return categories.isEmpty ? .excludingAll : .including(categories)
    }

    private func focusCamera(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: coordinate,
                distance: 900,
                heading: 0,
                pitch: 0
            )
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

    private func startNavigation(to place: Place) async {
        locationService.startNavigationUpdates()
        await navigation.start(
            to: place,
            from: locationService.currentLocation,
            route: store.selectedPlace?.id == place.id ? store.route : nil
        )

        guard navigation.isNavigating else {
            locationService.startEfficientUpdates()
            return
        }

        await liveActivityController.startTracking(
            place: place,
            deviceHeadingDegrees: locationService.headingDegrees
        )
        if var snapshot = navigation.snapshot {
            snapshot = snapshot.withArrowRotation(
                navigation.arrowRotation(
                    deviceHeadingDegrees: locationService.headingDegrees,
                    from: locationService.currentLocation
                )
            )
            await liveActivityController.updateNavigation(place: place, snapshot: snapshot)
        }
        isShowingNavigation = true
    }
}

private enum PresentedSheet: String, Identifiable {
    case settings
    case account

    var id: String { rawValue }
}

// MARK: - Bottom Sheet

private struct PlaceDrawer: View {
    @Binding var isExpanded: Bool
    let mapScope: Namespace.ID
    let isMapRotated: Bool
    let showAccount: () -> Void
    let showSettings: () -> Void
    let focusUserLocation: () -> Void
    let startNavigation: (Place) -> Void

    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var accountManager: AccountManager
    @EnvironmentObject private var savedPlacesStore: SavedPlacesStore
    @EnvironmentObject private var categoryStore: CategoryStore
    @EnvironmentObject private var profileStore: ProfileStore

    @State private var searchQuery = ""
    @State private var searchResults: [Place] = []
    @State private var isSearching = false

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
    private var hiddenAmount: CGFloat {
        max(0, contentHeight - headerHeight)
    }

    /// 카드를 아래로 밀어 둔 정도. 0이면 완전히 펼쳐진 상태입니다.
    private var offsetY: CGFloat {
        let base = dragAnchor ?? (isExpanded ? 0 : hiddenAmount)
        return min(hiddenAmount, max(0, base + dragDelta))
    }

    private var progress: CGFloat {
        hiddenAmount <= 0 ? 0 : 1 - offsetY / hiddenAmount
    }

    var body: some View {
        // 지도 컨트롤 · 카테고리 칩 · 카드를 한 컨테이너에 넣고 통째로 밀어 올립니다.
        // 이렇게 해야 드래그 중에 Map이 다시 그려지지 않아 움직임이 매끄럽습니다.
        VStack(alignment: .trailing, spacing: TossSpacing.m) {
            mapControls
                .padding(.trailing, TossEdge.floatingInset)
                .opacity(1 - progress)
                .allowsHitTesting(progress < 0.4)

            categoryChips

            card
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        // 여기에는 암시적 애니메이션을 붙이지 않습니다.
        // 드래그 중에는 손가락을 그대로 따라가야 하고, 놓을 때만 withAnimation으로 붙입니다.
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

            TossFloatingCircleButton(
                systemName: "arrow.clockwise",
                label: "주변 장소 새로고침",
                showsProgress: store.isLoading
            ) {
                refreshPlaces()
            }
        }
        .animation(TossMotion.quick, value: isMapRotated)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TossSpacing.s) {
                ForEach(categoryStore.visibleCategories) { category in
                    TossChip(
                        title: category.title,
                        systemImage: category.symbolName,
                        isSelected: categoryStore.isEnabled(category)
                    ) {
                        categoryStore.toggle(category)
                        refreshPlaces()
                    }
                }

                // 마지막 칩은 카테고리 관리로 바로 들어가는 입구입니다.
                Button(action: showSettings) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("카테고리")
                            .font(TossFont.buttonSmall)
                    }
                    .foregroundStyle(TossColor.blue)
                    .padding(.horizontal, 14)
                    .frame(minHeight: TossSize.chipHeight)
                    .background(TossColor.blueWeak, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(TossScaleButtonStyle())
                .accessibilityLabel("카테고리 추가 및 관리")
            }
            .padding(.horizontal, TossEdge.screenInset)
            .padding(.vertical, 2)
            .tossShadow(.floating)
        }
        .scrollIndicators(.hidden)
        // 칩 그림자가 스크롤뷰 경계에 잘리지 않게 합니다.
        .scrollClipDisabled()
    }

    private func refreshPlaces() {
        Task {
            await store.refreshPlaces(
                from: locationService.currentLocation,
                categories: categoryStore.activeCategories,
                force: true
            )
        }
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
            // 0.5pt 미만의 미세한 변화는 무시해서 offset이 진동하지 않게 합니다.
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

    /// 끌어올린 만큼 드러나는 부분.
    private var expandedBlock: some View {
        VStack(alignment: .leading, spacing: TossSpacing.m) {
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
            withAnimation(TossMotion.snappy) {
                isExpanded.toggle()
            }
        } label: {
            TossSheetHandle()
                .frame(maxWidth: .infinity, minHeight: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "장소 목록 접기" : "장소 목록 펼치기")
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: TossSpacing.s) {
            HStack(spacing: TossSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(TossColor.textTertiary)

                TextField("어디로 갈까요?", text: $searchQuery)
                    .font(TossFont.body)
                    .foregroundStyle(TossColor.textPrimary)
                    .tint(TossColor.blue)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onTapGesture {
                        withAnimation(TossMotion.snappy) {
                            isExpanded = true
                        }
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
            .background(TossColor.surfaceAlt, in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))

            DrawerIconButton(
                systemName: "slider.horizontal.3",
                label: "카테고리 설정",
                action: showSettings
            )

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
            .accessibilityLabel(accountManager.isSignedIn ? "내 FastMap 계정" : "프로필과 계정")
        }
    }

    // MARK: List

    @ViewBuilder
    private var expandedContent: some View {
        if isSearching {
            loadingState("장소를 찾고 있어요")
        } else if !searchResults.isEmpty {
            placeList(searchResults)
        } else if store.isLoading {
            loadingState("주변 장소를 찾고 있어요")
        } else if store.places.isEmpty {
            TossEmptyState(
                systemImage: "map",
                title: "주변에 장소가 없어요",
                message: "다른 카테고리를 골라보거나\n잠시 후 다시 시도해 주세요."
            )
            .frame(minHeight: 170)
        } else {
            placeList(store.places)
        }
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

    private func placeList(_ places: [Place]) -> some View {
        VStack(alignment: .leading, spacing: TossSpacing.s) {
            TossSectionHeader(
                title: searchResults.isEmpty ? "주변 장소" : "검색 결과",
                trailing: "가까운 순 · \(places.count)곳"
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(places) { place in
                        HStack(spacing: 0) {
                            Button {
                                searchQuery = searchResults.isEmpty ? searchQuery : place.name
                                Task {
                                    await store.select(place, from: locationService.currentLocation)
                                }
                            } label: {
                                PlaceRow(place: place, isSelected: place == store.selectedPlace)
                            }
                            .buttonStyle(TossPressableStyle(cornerRadius: TossRadius.field))
                            .accessibilityLabel("\(place.name), \(GeoMath.formattedDistance(place.distanceMeters))")
                            .accessibilityValue(place == store.selectedPlace ? "선택됨" : "")

                            BookmarkButton(isSaved: savedPlacesStore.contains(place)) {
                                toggleSavedPlace(place)
                            }
                        }

                        if place.id != places.last?.id {
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

    // MARK: CTA

    @ViewBuilder
    private var navigationControls: some View {
        if let selectedPlace = store.selectedPlace {
            VStack(spacing: TossSpacing.m) {
                TossDivider()

                HStack(alignment: .top, spacing: TossSpacing.m) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedPlace.name)
                            .font(TossFont.title2)
                            .foregroundStyle(TossColor.textPrimary)
                            .lineLimit(1)

                        Text(routeSummary)
                            .font(TossFont.callout)
                            .foregroundStyle(TossColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: TossSpacing.xxs)

                    BookmarkButton(isSaved: savedPlacesStore.contains(selectedPlace)) {
                        toggleSavedPlace(selectedPlace)
                    }
                }

                HStack(spacing: TossSpacing.s) {
                    // 보조 동작은 아이콘만 남겨서 주 버튼이 화면을 꽉 채우게 합니다.
                    Button {
                        openWalkingDirections(to: selectedPlace)
                    } label: {
                        Image(systemName: "map")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .buttonStyle(TossSecondaryButtonStyle())
                    .frame(width: TossSize.ctaHeight)
                    .accessibilityLabel("Apple 지도로 길안내")

                    Button {
                        startNavigation(selectedPlace)
                    } label: {
                        Text("길 안내 시작")
                            .lineLimit(1)
                    }
                    .buttonStyle(TossPrimaryButtonStyle())
                }
            }
        }
    }

    private var routeSummary: String {
        guard let route = store.route else {
            return "경로를 계산하고 있어요"
        }

        let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
        return "걸어서 약 \(minutes)분 · \(GeoMath.formattedDistance(route.distance))"
    }

    private func openWalkingDirections(to place: Place) {
        place.mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ]
        )
    }

    private func toggleSavedPlace(_ place: Place) {
        guard accountManager.isSignedIn else {
            showAccount()
            return
        }

        Task {
            await savedPlacesStore.toggle(place)
        }
    }

    private func runSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isSearching = true
        defer { isSearching = false }

        searchResults = await NearbyPlaceService().searchPlaces(
            query: query,
            around: locationService.currentLocation
        )

        if let firstResult = searchResults.first {
            await store.select(firstResult, from: locationService.currentLocation)
        }
    }
}

// MARK: - Pieces

private struct DrawerIconButton: View {
    let systemName: String
    let label: String
    var isAccented = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isAccented ? TossColor.blue : TossColor.textSecondary)
                .frame(width: TossSize.fieldHeight, height: TossSize.fieldHeight)
                .background(
                    isAccented ? TossColor.blueWeak : TossColor.surfaceAlt,
                    in: RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous))
        }
        .buttonStyle(TossScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

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
        .accessibilityLabel(isSaved ? "저장 취소" : "장소 저장")
    }
}

private struct PlaceRow: View {
    let place: Place
    let isSelected: Bool

    var body: some View {
        HStack(spacing: TossSpacing.m) {
            TossIconBadge(systemName: place.category.symbolName, tint: place.category.tint, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(TossFont.headline)
                    .foregroundStyle(TossColor.textPrimary)
                    .lineLimit(1)
                Text(place.address)
                    .font(TossFont.caption)
                    .foregroundStyle(TossColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(GeoMath.formattedDistance(place.distanceMeters))
                    .font(TossFont.bodyStrong)
                    .foregroundStyle(isSelected ? TossColor.blue : TossColor.textPrimary)
                Text(GeoMath.directionText(for: place.bearingDegrees))
                    .font(TossFont.footnote)
                    .foregroundStyle(TossColor.textTertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, TossSpacing.m)
        .padding(.horizontal, TossSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: TossRadius.field, style: .continuous)
                .fill(isSelected ? TossColor.blueWeak : .clear)
        )
    }
}

struct RadarMapView_Previews: PreviewProvider {
    static var previews: some View {
        RadarMapView()
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
