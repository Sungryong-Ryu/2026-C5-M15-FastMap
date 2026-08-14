import MapKit
import SwiftUI

struct RadarMapView: View {
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: .seoulCityHall,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    @State private var isShowingSettings = false
    @State private var isDrawerExpanded = false
    @State private var searchQuery = ""
    @State private var searchResults: [Place] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition, selection: $store.selectedPlace) {
                    UserAnnotation()

                    ForEach(store.places) { place in
                        Marker(place.name, systemImage: place.category.symbolName, coordinate: place.coordinate)
                            .tint(place.category.tint)
                            .tag(place)
                    }

                    if let route = store.route {
                        MapPolyline(route.polyline)
                            .stroke(.blue, lineWidth: 5)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        .black.opacity(0.16),
                        .clear,
                        .black.opacity(0.22)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                PlaceDrawer(isExpanded: $isDrawerExpanded)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                topControlPanel
            }
            .sheet(isPresented: $isShowingSettings) {
                CategorySettingsView()
                    .presentationDetents([.medium, .large])
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
        }
    }

    private var topControlPanel: some View {
        VStack(spacing: 12) {
            topBar
            searchBar
            searchResultsList
            categoryControls
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FastMap")
                    .font(.title3.weight(.bold))
                Text(topStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            iconButton(systemName: "location.fill", label: "현재 위치로 이동") {
                locationService.startEfficientUpdates()
                focusCamera(on: locationService.currentLocation)
                Task {
                    await store.refreshPlaces(from: locationService.currentLocation, force: true)
                }
            }

            iconButton(systemName: "slider.horizontal.3", label: "설정") {
                isShowingSettings = true
            }
        }
    }

    private var topStatusText: String {
        if store.isLoading {
            return "주변 장소를 새로 찾는 중"
        }

        if locationService.isUsingFallbackLocation {
            return "서울 시청 위치로 미리보기 중"
        }

        if let selectedPlace = store.selectedPlace {
            return "\(selectedPlace.category.title) · \(GeoMath.formattedDistance(selectedPlace.distanceMeters))"
        }

        return "가까운 장소를 한 번에 확인"
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
            if !store.selectedCategories.contains(category) {
                store.selectedCategories.insert(category)
            }
            isDrawerExpanded = true
            Task {
                await store.refreshPlaces(from: locationService.currentLocation, force: true)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: category.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isSelected ? .white : category.tint)
                    .background(isSelected ? category.tint : category.tint.opacity(0.14))
                    .clipShape(Circle())

                Text(category.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .frame(height: 34)
            .background(isSelected ? Color(.systemBackground) : Color(.secondarySystemBackground).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? category.tint.opacity(0.45) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("장소, 주소 검색", text: $searchQuery)
                .font(.subheadline.weight(.medium))
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    Task {
                        await runSearch()
                    }
                }

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if !searchResults.isEmpty {
            VStack(spacing: 6) {
                ForEach(searchResults.prefix(3)) { place in
                    Button {
                        searchQuery = place.name
                        searchResults = []
                        isDrawerExpanded = true
                        Task {
                            await store.select(place, from: locationService.currentLocation)
                        }
                    } label: {
                        SearchResultRow(place: place)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(.primary)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.black.opacity(0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            isDrawerExpanded = true
        }
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

private struct SearchResultRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(place.category.tint)

            VStack(alignment: .leading, spacing: 2) {
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

            Text(GeoMath.formattedDistance(place.distanceMeters))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlaceDrawer: View {
    @Binding var isExpanded: Bool
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var store: FastMapStore
    @EnvironmentObject private var liveActivityController: LiveActivityController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(.secondary.opacity(0.28))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            header

            if isExpanded {
                expandedContent
                liveActivityControls
            }
        }
        .padding(14)
        .frame(maxHeight: isExpanded ? 382 : 112)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 22, x: 0, y: 12)
        .gesture(
            DragGesture(minimumDistance: 16)
                .onEnded { value in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        isExpanded = value.translation.height < 0
                    }
                }
        )
    }

    @ViewBuilder
    private var expandedContent: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 112)
        } else if store.places.isEmpty {
            ContentUnavailableView(
                "주변 장소가 없습니다",
                systemImage: "map",
                description: Text("다른 카테고리를 선택하거나 잠시 후 다시 시도해보세요.")
            )
            .frame(minHeight: 130)
        } else {
            VStack(spacing: 8) {
                if let selectedPlace = store.selectedPlace {
                    DestinationCard(place: selectedPlace)
                }

                ForEach(store.places.filter { $0 != store.selectedPlace }.prefix(3)) { place in
                    Button {
                        Task {
                            await store.select(place, from: locationService.currentLocation)
                        }
                    } label: {
                        PlaceRow(place: place, isSelected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("지금 가장 가까운 곳")
                    .font(.headline.weight(.bold))
                Text(summaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            iconButton(systemName: isExpanded ? "chevron.down" : "chevron.up", label: isExpanded ? "패널 접기" : "패널 펼치기") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            }

            iconButton(systemName: "arrow.clockwise", label: "주변 장소 새로고침") {
                Task {
                    await store.refreshPlaces(from: locationService.currentLocation, force: true)
                }
            }
        }
    }

    private var summaryText: String {
        if let selectedPlace = store.selectedPlace {
            return "\(selectedPlace.name) · \(GeoMath.formattedDistance(selectedPlace.distanceMeters)) \(GeoMath.directionText(for: selectedPlace.bearingDegrees))"
        }
        return store.selectedCategories.map(\.title).sorted().joined(separator: " / ")
    }

    private var liveActivityControls: some View {
        HStack(spacing: 10) {
            Label(
                liveActivityController.statusText,
                systemImage: liveActivityController.isRunning ? "lock.display" : "dot.radiowaves.left.and.right"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer(minLength: 8)

            if liveActivityController.isRunning {
                Button {
                    Task {
                        await liveActivityController.end()
                    }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Live Activity 종료")
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
                    Label("라이브 시작", systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(height: 34)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedPlace == nil)
            }
        }
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.primary)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct DestinationCard: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(place.category.tint.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: place.category.symbolName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(place.category.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(place.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(GeoMath.formattedDistance(place.distanceMeters))
                    .font(.headline.weight(.bold))
                Text(GeoMath.directionText(for: place.bearingDegrees))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(place.category.tint)
            }
        }
        .padding(12)
        .background(place.category.tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(place.category.tint.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct PlaceRow: View {
    let place: Place
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(place.category.tint)
                .frame(width: 34, height: 34)
                .background(place.category.tint.opacity(0.14))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(place.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(GeoMath.formattedDistance(place.distanceMeters))
                    .font(.subheadline.weight(.bold))
                Text(GeoMath.directionText(for: place.bearingDegrees))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemBackground).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
