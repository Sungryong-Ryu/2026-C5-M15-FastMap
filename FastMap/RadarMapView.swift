import MapKit
import SwiftUI

struct RadarMapView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @Namespace private var mapScope

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .seoulCityHall,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    @State private var isShowingSettings = false
    @State private var isDrawerExpanded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            map

            bottomOverlay
        }
        .sheet(isPresented: $isShowingSettings) {
            CategorySettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            focusCamera(on: locationService.currentLocation)
        }
        .onChange(of: locationService.currentLocation) { _, newLocation in
            focusCamera(on: newLocation)
        }
        .onChange(of: store.selectedPlace) { _, newPlace in
            if let newPlace {
                focusCamera(on: newPlace.coordinate)
            }
        }
        .mapScope(mapScope)
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $store.selectedPlace, scope: mapScope) {
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
                    .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: pointOfInterestFilter))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    private var bottomOverlay: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Spacer()

            mapControlCluster

            PlaceDrawer(
                isExpanded: $isDrawerExpanded,
                showSettings: { isShowingSettings = true }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, -26)
    }

    @ViewBuilder
    private var mapControlCluster: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                controlButtons
            }
        } else {
            controlButtons
        }
    }

    private var controlButtons: some View {
        VStack(spacing: 8) {
            MapCompass(scope: mapScope)
                .mapControlVisibility(.visible)
                .accessibilityLabel("지도를 북쪽 방향으로 돌리기")

            GlassCircleButton(systemName: "location.fill", label: "현재 위치로 이동") {
                locationService.startEfficientUpdates()
                focusCamera(on: locationService.currentLocation)
            }

            GlassCircleButton(systemName: "arrow.clockwise", label: "주변 장소 새로고침") {
                Task {
                    await store.refreshPlaces(from: locationService.currentLocation, force: true)
                }
            }
        }
    }

    private var pointOfInterestFilter: PointOfInterestCategories {
        let categories = store.selectedCategories.flatMap { category in
            category.pointOfInterestCategories ?? []
        }

        return categories.isEmpty
            ? .all
            : .including(categories)
    }

    private func focusCamera(on coordinate: CLLocationCoordinate2D) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            )
        )
    }
}

private struct GlassCircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(label)
        } else {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }
}

private struct PlaceDrawer: View {
    @Binding var isExpanded: Bool
    let showSettings: () -> Void

    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var liveActivityController: LiveActivityController

    @State private var searchQuery = ""
    @State private var searchResults: [Place] = []
    @State private var isSearching = false

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                drawerContent
                    .glassEffect(.regular, in: .rect(cornerRadius: 26))
            } else {
                drawerContent
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
            }
        }
        .animation(.snappy(duration: 0.34), value: isExpanded)
        .gesture(
            DragGesture(minimumDistance: 18)
                .onEnded { value in
                    guard abs(value.translation.height) > 24 else { return }
                    withAnimation(.snappy(duration: 0.34)) {
                        isExpanded = value.translation.height < 0
                    }
                }
        )
    }

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 7)

            searchBar
            categoryControls

            if isExpanded {
                Divider()
                    .padding(.horizontal, 2)

                expandedContent
                navigationControls
                liveActivityControls
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 30)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("FastMap 검색", text: $searchQuery)
                .font(.body)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.34)) {
                        isExpanded = true
                    }
                }
                .onSubmit {
                    Task { await runSearch() }
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            } else {
                Button(action: showSettings) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("FastMap 설정")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(.secondarySystemBackground).opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var categoryControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategory.quickCategories) { category in
                    categoryButton(category)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func categoryButton(_ category: PlaceCategory) -> some View {
        let isSelected = store.selectedCategories.contains(category)

        return Button {
            store.focusedCategory = category
            if !isSelected {
                store.selectedCategories.insert(category)
            }
            withAnimation(.snappy(duration: 0.34)) {
                isExpanded = true
            }
            Task {
                await store.refreshPlaces(from: locationService.currentLocation, force: true)
            }
        } label: {
            Label(category.title, systemImage: category.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(isSelected ? category.tint : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var expandedContent: some View {
        if isSearching {
            ProgressView("장소 검색 중")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if !searchResults.isEmpty {
            placeList(searchResults)
        } else if store.isLoading {
            ProgressView("주변 장소 찾는 중")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if store.places.isEmpty {
            ContentUnavailableView(
                "주변 장소가 없습니다",
                systemImage: "map",
                description: Text("다른 카테고리를 선택하거나 잠시 후 다시 시도해보세요.")
            )
            .frame(minHeight: 174)
        } else {
            placeList(store.places)
        }
    }

    private func placeList(_ places: [Place]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(searchResults.isEmpty ? "주변 장소" : "검색 결과")
                    .font(.headline)
                Spacer()
                Text("가까운 순")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            ForEach(places.prefix(3)) { place in
                Button {
                    searchQuery = searchResults.isEmpty ? searchQuery : place.name
                    Task {
                        await store.select(place, from: locationService.currentLocation)
                    }
                } label: {
                    PlaceRow(place: place, isSelected: place == store.selectedPlace)
                }
                .buttonStyle(.plain)

                if place.id != places.prefix(3).last?.id {
                    Divider()
                        .padding(.leading, 50)
                }
            }
        }
        .frame(maxHeight: 218, alignment: .top)
    }

    private var liveActivityControls: some View {
        HStack(spacing: 10) {
            Label(
                liveActivityController.statusText,
                systemImage: liveActivityController.isRunning ? "location.fill.viewfinder" : "dot.radiowaves.left.and.right"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 4)

            if liveActivityController.isRunning {
                Button("종료", role: .destructive) {
                    Task { await liveActivityController.end() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    Task {
                        if let selectedPlace = store.selectedPlace {
                            locationService.startEfficientUpdates()
                            await liveActivityController.startTracking(
                                place: selectedPlace,
                                deviceHeadingDegrees: locationService.headingDegrees
                            )
                        }
                    }
                } label: {
                    Label("잠금화면 안내", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(store.selectedPlace == nil)
            }
        }
        .frame(minHeight: 34)
    }

    @ViewBuilder
    private var navigationControls: some View {
        if let selectedPlace = store.selectedPlace {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("도보 길찾기")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(routeSummary)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                AppleMapsDirectionsButton {
                    openWalkingDirections(to: selectedPlace)
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var routeSummary: String {
        guard let route = store.route else {
            return "경로 계산 중"
        }

        let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
        return "약 \(minutes)분 · \(GeoMath.formattedDistance(route.distance))"
    }

    private func openWalkingDirections(to place: Place) {
        place.mapItem.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
            ]
        )
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

private struct AppleMapsDirectionsButton: View {
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Label("Apple 지도 길안내", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 32)
            }
            .buttonStyle(.glassProminent)
        } else {
            Button(action: action) {
                Label("Apple 지도 길안내", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct PlaceRow: View {
    let place: Place
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(place.category.tint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(place.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(GeoMath.formattedDistance(place.distanceMeters))
                    .font(.subheadline.weight(.semibold))
                Text(GeoMath.directionText(for: place.bearingDegrees))
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.blue : Color.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
    }
}

struct RadarMapView_Previews: PreviewProvider {
    static var previews: some View {
        RadarMapView()
            .environmentObject(LocationService.preview)
            .environmentObject(FastMapStore.preview)
            .environmentObject(LiveActivityController())
    }
}
