//
//  CafeStore.swift
//  CoFFMap
//
//  화면이 보는 상태 전부. 카페 목록, 선택, 태그 필터, 거리, 도보 경로.
//
//  데이터 경로는 검색 중심 좌표에 따라 자동으로 갈립니다.
//  - 대한민국 안에서는 Kakao Local API. 국내 카페 데이터가 훨씬 촘촘합니다.
//  - 해외에서는 Apple MapKit. Kakao 키가 없거나 국내 호출이 실패했을 때도 Apple로 내려갑니다.
//
//  Kakao 응답은 저장하지 않습니다. 메모리에만 두고, 즐겨찾기처럼 저장이 필요한 순간에만
//  `AppleCafeResolver`로 Apple 값으로 바꿔서 넘깁니다.
//
//  **어디를 보고 있는가(`SearchScope`)가 이 파일의 중심입니다.**
//  내 주변인지, 내가 있는 행정 구역 전체인지, 지도로 옮겨 간 다른 지역인지에 따라
//  거리를 재는 기준점(`searchOrigin`)과 다시 불러올지 말지가 달라집니다.
//

import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class CafeStore: ObservableObject {

    /// 지금 어느 데이터를 보고 있는지. 하단 시트에 한 줄로 알려 줍니다.
    enum DataSource: Equatable {
        case kakao
        case appleInternational
        case appleFallback(reason: String)

        var noticeText: String? {
            switch self {
            case .kakao: nil
            case .appleInternational: "Apple MapKit으로 검색 중 · 해외 지역"
            case .appleFallback(let reason): "Apple 지도로 찾는 중 · \(reason)"
            }
        }

        var isWarning: Bool {
            if case .appleFallback = self { return true }
            return false
        }
    }

    /// 지도에서 옮겨 가 훑고 있는 영역.
    struct MapArea: Equatable, Sendable {
        /// 그 지역 이름. 못 알아내면 nil입니다.
        let title: String?
        let center: CLLocationCoordinate2D
        let radiusMeters: CLLocationDistance
    }

    /// 지금 무엇을 보고 있는지.
    enum SearchScope: Equatable {
        /// 내 위치 주변. 걸으면 따라옵니다.
        case nearby
        /// 내가 있는 행정 구역 전체. 걸어도 목록은 그대로입니다.
        case region(RegionScope)
        /// 지도로 옮겨 간 다른 지역. 내 위치와 무관합니다.
        case mapArea(MapArea)
    }

    /// 필터를 통과한, 화면에 보여 줄 카페.
    @Published private(set) var cafes: [Cafe] = []
    @Published var selectedCafe: Cafe?
    /// 켜져 있는 태그. 비어 있으면 모든 유형을 보여 줍니다.
    @Published private(set) var activeTags: Set<CafeTag> = []
    /// 기준점에서 이 거리 안에 있는 카페만 보여 줍니다. nil이면 "전체"입니다.
    @Published private(set) var activeRadiusMeters: Int? = defaultRadiusMeters
    /// 지금 어디를 보고 있는지.
    @Published private(set) var scope: SearchScope = .nearby
    /// 목록의 거리와 거리 필터가 어느 점을 기준으로 계산됐는지.
    ///
    /// 내 주변·지역 전체에서는 내 위치, 다른 지역을 볼 때는 그 지도 화면의 중심입니다.
    /// 포항에 서서 속초를 볼 때 "245km"만 늘어놓으면 그 지역 안에서 비교가 안 되니까요.
    @Published private(set) var searchOrigin: CLLocationCoordinate2D = .seoulCityHall
    @Published private(set) var route: MKRoute?
    @Published private(set) var isLoading = false
    @Published private(set) var dataSource: DataSource = .kakao
    @Published var errorMessage: String?

    /// 필터를 걸기 전의 원본. 태그만 바꿀 때는 다시 호출하지 않고 여기서 걸러 냅니다.
    private var fetchedCafes: [Cafe] = []
    private var lastFetchLocation: CLLocationCoordinate2D?
    private var lastFetchTagKey: String = ""
    /// 마지막으로 물어본 반경. 거리를 바꾸면 제자리에서도 다시 물어봐야 합니다.
    private var lastFetchRadius: CLLocationDistance?
    /// 빠르게 필터를 바꿨을 때 먼저 시작한 검색이 나중 결과를 덮지 못하게 하는 세대 번호.
    private var searchRevision = 0

    /// 내 주변을 한 번에 훑는 반경. 거리 선택지의 최대값(1km)보다 넉넉해야
    /// 걸어 다닐 때 가장자리 카페가 깜빡이며 사라지지 않습니다.
    private let searchRadius: CLLocationDistance = 1_500
    /// 이만큼 움직이기 전에는 다시 부르지 않습니다. Kakao 호출을 아끼려는 장치입니다.
    private let refetchThresholdMeters: CLLocationDistance = 250

    private let appleResolver = AppleCafeResolver()
    private let territoryResolver: SearchTerritoryResolver
    private let regionResolver: RegionScopeResolver

    init() {
        let territoryResolver = SearchTerritoryResolver()
        self.territoryResolver = territoryResolver
        regionResolver = RegionScopeResolver(territoryResolver: territoryResolver)
    }

    // MARK: - 거리 선택지

    /// 사용자가 고를 수 있는 거리. 여기에 행정 구역/지도 화면 전체를 뜻하는 `nil`이 붙습니다.
    static let distanceOptions = [50, 100, 200, 500, 1_000]
    static let defaultRadiusMeters = 1_000
    /// 도보 길안내를 권할 수 있는 한계. 다른 지역을 구경할 때는 이보다 훨씬 멀어집니다.
    static let walkableLimitMeters: CLLocationDistance = 30_000
    /// 지도에 찍을 마커 상한. 지역 전체는 수백 곳이 나와서 다 찍으면 지도가 버벅입니다.
    private static let maxMapMarkers = 120

    static func distanceLabel(_ meters: Int) -> String {
        meters >= 1_000 ? "\(meters / 1_000)km" : "\(meters)m"
    }

    var hasActiveFilters: Bool {
        !activeTags.isEmpty || activeRadiusMeters != Self.defaultRadiusMeters
    }

    /// 50~500m처럼 촘촘한 거리를 켰을 때만 정밀 위치가 필요합니다.
    /// 그 외에는 배터리를 아끼는 갱신으로 충분합니다.
    var needsPreciseLocation: Bool {
        guard let activeRadiusMeters else { return false }
        return activeRadiusMeters <= 500
    }

    /// 지도로 옮겨 가 다른 지역을 보는 중인지.
    var isBrowsingElsewhere: Bool {
        if case .mapArea = scope { return true }
        return false
    }

    /// 목록 제목.
    var scopeTitle: String {
        switch scope {
        case .nearby:
            "주변 카페"
        case .region(let region):
            "\(region.title) 카페"
        case .mapArea(let area):
            area.title.map { "\($0) 카페" } ?? "이 지역 카페"
        }
    }

    /// 목록 제목 옆에 붙는 한 줄.
    func scopeDetail(count: Int) -> String {
        switch scope {
        case .nearby:
            if let activeRadiusMeters {
                return "\(Self.distanceLabel(activeRadiusMeters)) 안 · \(count)곳"
            }
            return "가까운 순 · \(count)곳"
        case .region:
            return "지역 전체 · \(count)곳"
        case .mapArea:
            if let activeRadiusMeters {
                return "\(Self.distanceLabel(activeRadiusMeters)) 안 · \(count)곳"
            }
            return "지도 화면 전체 · \(count)곳"
        }
    }

    /// 지도에 찍을 카페. 가까운 순으로 잘라 냅니다.
    var mapCafes: [Cafe] { Array(cafes.prefix(Self.maxMapMarkers)) }

    // MARK: - 태그 필터

    /// 프랜차이즈와 개인카페는 같이 켤 수 없습니다. 둘 다 켜면 결과가 항상 비니까요.
    private static let exclusivePairs: [Set<CafeTag>] = [[.franchise, .independent]]

    func isActive(_ tag: CafeTag) -> Bool { activeTags.contains(tag) }

    func toggle(_ tag: CafeTag) {
        if activeTags.contains(tag) {
            activeTags.remove(tag)
        } else {
            // 서로 배타적인 짝이 켜져 있으면 끄고 들어갑니다.
            for pair in Self.exclusivePairs where pair.contains(tag) {
                activeTags.subtract(pair)
            }
            activeTags.insert(tag)
        }
        applyFilter()
    }

    func clearTags() {
        activeTags.removeAll()
        applyFilter()
    }

    // MARK: - 거리 필터

    func isActive(radiusMeters: Int?) -> Bool { activeRadiusMeters == radiusMeters }

    func isWithinActiveRadius(_ cafe: Cafe) -> Bool {
        guard let activeRadiusMeters else { return true }
        return cafe.distanceMeters <= CLLocationDistance(activeRadiusMeters)
    }

    /// 거리를 골랐을 때.
    ///
    /// "전체"(nil)의 뜻은 지금 무엇을 보고 있느냐에 따라 다릅니다.
    /// - 내 주변을 보고 있었다면 → 내가 있는 행정 구역 전체를 새로 훑습니다.
    /// - 이미 다른 지역을 보고 있었다면 → 그 지역에서 받아 둔 카페 전부를 보여 줍니다.
    func setRadius(_ radiusMeters: Int?, around userLocation: CLLocationCoordinate2D) async {
        // 이미 켜져 있는 칩을 다시 눌러도 다시 훑지 않습니다. "전체"는 호출이 무거워서
        // 실수로 한 번 더 누르는 것만으로 수십 번 부르면 곤란합니다.
        guard radiusMeters != activeRadiusMeters else { return }
        activeRadiusMeters = radiusMeters

        switch scope {
        case .mapArea(let area):
            // 넓은 지도 화면을 성기게 훑은 결과만 거리로 잘라 쓰면 50m 안 카페를 놓칠 수
            // 있습니다. 선택한 거리에 맞춰 지도 중심을 다시 촘촘하게 검색합니다.
            isLoading = true
            defer { isLoading = false }
            let revision = beginSearch()
            await load(
                center: area.center,
                radiusMeters: mapAreaFetchRadius(for: area),
                origin: area.center,
                revision: revision
            )
            await updateRoute(from: userLocation)

        case .region:
            // 지역 전체를 보다가 좁은 반경으로 돌아옵니다.
            // 지역 목록은 내 주변이 성길 수 있어(격자로 훑은 결과입니다) 주변을 다시 받습니다.
            scope = .nearby
            applyFilter()
            await refreshNearby(from: userLocation, force: true)

        case .nearby:
            if radiusMeters == nil {
                await showEntireRegion(around: userLocation)
            } else {
                applyFilter()
                await refreshNearby(from: userLocation, force: false)
            }
        }
    }

    /// 켠 태그를 **모두** 가진 카페만 남깁니다.
    /// "강변 + 베이커리"는 강변에 있는 베이커리 카페라는 뜻이 됩니다.
    private func applyFilter() {
        let filtered = fetchedCafes.filter { cafe in
            let matchesTags = activeTags.isEmpty || cafe.tags.isSuperset(of: activeTags)
            return matchesTags && isWithinActiveRadius(cafe)
        }

        cafes = filtered.sorted { $0.distanceMeters < $1.distanceMeters }

        // 태그 때문에 걸러진 카페가 선택돼 있으면 선택을 놓습니다.
        //
        // 단, 주변 목록에 애초에 없던 선택은 건드리지 않습니다. 검색 결과나 저장 목록에서
        // 고른 카페는 반경 밖일 수 있고, 지도도 그런 선택을 따로 찍어 줍니다.
        // 여기서 같이 지워 버리면 멀리 있는 카페로 길을 찾는 도중, 250m 걸을 때마다
        // 도는 새로고침에 선택과 경로가 통째로 사라집니다.
        if let selectedCafe,
           fetchedCafes.contains(selectedCafe),
           !cafes.contains(selectedCafe) {
            self.selectedCafe = nil
            route = nil
        }
    }

    // MARK: - 불러오기

    /// 위치가 바뀌었을 때 부릅니다. 무엇을 보고 있느냐에 따라 반응이 다릅니다.
    func refresh(from location: CLLocationCoordinate2D, force: Bool = false) async {
        switch scope {
        case .mapArea(let area):
            // 내가 걸어 다닌다고 다른 지역의 목록을 흔들면 안 됩니다.
            // 태그를 바꿔 다시 받아야 할 때(force)만 그 지역을 다시 훑습니다.
            guard force else { return }
            isLoading = true
            let revision = beginSearch()
            await load(
                center: area.center,
                radiusMeters: mapAreaFetchRadius(for: area),
                origin: area.center,
                revision: revision
            )
            isLoading = false
            await updateRoute(from: location)

        case .region(let region):
            // 지역 전체 목록은 내가 몇 걸음 걷는다고 달라지지 않습니다. 거리만 다시 잽니다.
            recomputeDistances(from: location)
            if force {
                isLoading = true
                let revision = beginSearch()
                await load(region: region, origin: location, revision: revision)
                isLoading = false
            }
            await updateRoute(from: location)

        case .nearby:
            await refreshNearby(from: location, force: force)
        }
    }

    private func refreshNearby(from location: CLLocationCoordinate2D, force: Bool) async {
        let tagKey = currentTagKey
        let tagsChanged = tagKey != lastFetchTagKey
        let radius = nearbyFetchRadius
        let radiusChanged = radius != lastFetchRadius

        // API 재호출 기준(250m)보다 촘촘한 거리 필터를 위해, 기존 카페의 상대 거리부터
        // 매 위치 갱신마다 다시 계산합니다.
        recomputeDistances(from: location)

        if !force, !tagsChanged, !radiusChanged, let lastFetchLocation, !fetchedCafes.isEmpty {
            let moved = GeoMath.distanceMeters(from: lastFetchLocation, to: location)
            guard moved > refetchThresholdMeters else { return }
        }

        isLoading = true
        defer { isLoading = false }
        let revision = beginSearch()

        // 필터가 없을 때도 한 검색의 45곳 상한을 그대로 쓰면, 필터를 켠 뒤 이미 누락된
        // 후보는 되살릴 수 없습니다. 항상 영역을 포화도에 따라 나눠 전체 후보를 모읍니다.
        let fetched = await sweep(center: location, radiusMeters: radius, origin: location)

        guard revision == searchRevision else { return }

        lastFetchRadius = radius

        // 자동 선택은 하지 않습니다. 선택이 생기면 카메라가 그리로 움직여서,
        // 앱을 켤 때 현위치가 아닌 곳이 보이게 됩니다.
        apply(fetched, origin: location)
        await updateRoute(from: location)
    }

    /// 내 주변을 물어볼 반경. 켜 둔 거리에 맞춰 좁힙니다.
    ///
    /// 선택 거리보다 25% 넓게 받아 두면 사용자가 조금 움직여도 경계 카페가 바로 사라지지
    /// 않습니다. 50~200m 선택은 GPS 오차까지 감안해 최소 400m를 후보 수집 범위로 둡니다.
    private var nearbyFetchRadius: CLLocationDistance {
        guard let activeRadiusMeters else { return searchRadius }
        return min(searchRadius, max(CLLocationDistance(activeRadiusMeters) * 1.25, 400))
    }

    /// 거리 "전체" — 지금 있는 행정 구역을 통째로 훑습니다.
    ///
    /// 서울이면 자치구 하나(강남구), 그 밖에는 시·군 전체(포항시)입니다.
    /// 구역을 못 알아내면 조용히 내 주변 검색으로 물러납니다.
    func showEntireRegion(around location: CLLocationCoordinate2D) async {
        activeRadiusMeters = nil

        isLoading = true
        defer { isLoading = false }
        let revision = beginSearch()

        guard let region = await regionResolver.scope(at: location) else {
            guard revision == searchRevision else { return }
            scope = .nearby
            await refreshNearby(from: location, force: true)
            return
        }

        guard revision == searchRevision else { return }

        scope = .region(region)
        await load(region: region, origin: location, revision: revision)
        await updateRoute(from: location)
    }

    /// 지도에 보이는 영역을 훑습니다.
    ///
    /// 화면이 아직 내 위치 근처면 굳이 다른 모드로 넘어가지 않고 그냥 새로고침합니다.
    /// 그래야 "새로고침"과 "이 지역 검색"이 버튼 하나로 자연스럽게 이어집니다.
    func searchVisibleArea(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        userLocation: CLLocationCoordinate2D
    ) async {
        let staysNearMe = GeoMath.distanceMeters(from: center, to: userLocation) <= refetchThresholdMeters
            && radiusMeters <= searchRadius

        if staysNearMe {
            if activeRadiusMeters == nil {
                await showEntireRegion(around: userLocation)
            } else {
                scope = .nearby
                await refreshNearby(from: userLocation, force: true)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }
        let revision = beginSearch()

        let radius = min(max(radiusMeters, 400), RegionScopeResolver.maxRadiusMeters)
        let title = await regionResolver.title(at: center)
        guard revision == searchRevision else { return }
        scope = .mapArea(MapArea(title: title, center: center, radiusMeters: radius))
        // 다른 지역에서는 반경 필터를 풀어 둡니다. 그 지역에 처음 왔는데
        // 50m 칩이 켜져 있어 목록이 비는 상황을 막습니다.
        activeRadiusMeters = nil

        await load(center: center, radiusMeters: radius, origin: center, revision: revision)
        await updateRoute(from: userLocation)
    }

    /// 다른 지역을 보다가 내 주변으로 돌아옵니다.
    func returnToNearby(around location: CLLocationCoordinate2D) async {
        guard scope != .nearby else { return }
        scope = .nearby
        activeRadiusMeters = Self.defaultRadiusMeters
        isLoading = true
        defer { isLoading = false }
        await refreshNearby(from: location, force: true)
    }

    private func load(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        origin: CLLocationCoordinate2D,
        revision: Int
    ) async {
        let fetched = await sweep(center: center, radiusMeters: radiusMeters, origin: origin)
        guard revision == searchRevision else { return }
        apply(fetched, origin: origin)
    }

    /// 행정 구역 전체 검색은 원형 반경 밖으로 새어 나온 이웃 지역 결과를 주소로 한 번 더
    /// 걸러 냅니다. Kakao 결과에는 행정 주소가 항상 있으므로 서울 중구를 보는데 종로구
    /// 카페가 섞이는 일을 막을 수 있습니다. Apple 대체 결과는 주소 형식이 일정하지 않아
    /// 반경 결과를 그대로 둡니다.
    private func load(region: RegionScope, origin: CLLocationCoordinate2D, revision: Int) async {
        let fetched = await sweep(
            center: region.center,
            radiusMeters: region.radiusMeters,
            origin: origin
        )
        guard revision == searchRevision else { return }
        let cafesInRegion = fetched.filter { cafe in
            guard cafe.source == .kakao else { return true }
            return cafe.address.contains(region.title)
                || cafe.roadAddress?.contains(region.title) == true
        }
        apply(cafesInRegion, origin: origin)
    }

    /// 다른 지역을 보는 중의 "전체"는 재검색 버튼을 눌렀을 때 보이던 지도 범위이고,
    /// 숫자 거리는 그 지도 중심을 기준으로 한 촘촘한 검색 반경입니다.
    private func mapAreaFetchRadius(for area: MapArea) -> CLLocationDistance {
        guard let activeRadiusMeters else { return area.radiusMeters }
        return max(CLLocationDistance(activeRadiusMeters) * 1.25, 400)
    }

    // MARK: - 훑기

    /// 검색 영역을 훑고 합칩니다.
    ///
    /// Kakao는 한 조건에서 최대 45곳만 노출합니다. 결과가 45곳에 닿은 사각형만 네 칸으로
    /// 다시 나눠, 더 이상 포화되지 않을 때까지 조회합니다. 그래서 밀집 지역에서도 거리나
    /// 유형 필터를 켜기 전에 후보가 잘리는 일을 막습니다.
    private func sweep(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance,
        origin: CLLocationCoordinate2D
    ) async -> [Cafe] {
        let rectangle = Self.searchRectangle(center: center, radiusMeters: radiusMeters)
        let territory = await territoryResolver.territory(at: center)

        let collected: [Cafe]
        if territory == .international {
            dataSource = .appleInternational
            errorMessage = nil
            collected = await fetchFromApple(center: center, radiusMeters: radiusMeters)
        } else if let kakao = KakaoLocalService() {
            do {
                collected = try await fetchFromKakao(
                    kakao,
                    in: rectangle,
                    origin: origin
                )
                dataSource = .kakao
                errorMessage = nil
            } catch {
                let reason = (error as? KakaoLocalError)?.errorDescription ?? "Kakao 호출 실패"
                dataSource = .appleFallback(reason: reason)
                collected = await fetchFromApple(center: center, radiusMeters: radiusMeters)
            }
        } else {
            dataSource = .appleFallback(reason: "Kakao API 키 없음")
            collected = await fetchFromApple(center: center, radiusMeters: radiusMeters)
        }

        return dedupe(collected)
            .filter { GeoMath.distanceMeters(from: center, to: $0.coordinate) <= radiusMeters }
    }

    /// 영역을 덮을 검색 지점들. 넓을수록 지점을 늘립니다.
    private static func samplePoints(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) -> [(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance)] {
        // Apple MapKit 검색에서 좁은 영역은 한 번으로 충분합니다.
        if radiusMeters <= 800 {
            return [(center, radiusMeters)]
        }

        let ringCount = radiusMeters <= 8_000 ? 6 : 8
        let ringDistance = radiusMeters * 0.62
        let sampleRadius = radiusMeters * 0.55

        var points: [(center: CLLocationCoordinate2D, radiusMeters: CLLocationDistance)] = [
            (center, sampleRadius)
        ]

        for index in 0..<ringCount {
            let bearing = Double(index) / Double(ringCount) * 360
            let point = GeoMath.coordinate(
                from: center,
                distanceMeters: ringDistance,
                bearingDegrees: bearing
            )
            points.append((point, sampleRadius))
        }

        return points
    }

    /// 카테고리 결과를 빠짐없이 모은 뒤, 선택한 추정 유형의 키워드 결과를 유형별로 보강합니다.
    private func fetchFromKakao(
        _ service: KakaoLocalService,
        in rectangle: KakaoSearchRectangle,
        origin: CLLocationCoordinate2D
    ) async throws -> [Cafe] {
        var collected = try await adaptiveKakaoSearch(
            service,
            kind: .category,
            in: rectangle,
            origin: origin
        )

        let keywordSearches = activeTags.flatMap { tag in
            tag.keywordQueries.map { (tag: tag, query: $0) }
        }

        // 한 키워드가 실패해도 카테고리 결과와 다른 유형 검색까지 버리지는 않습니다.
        for search in keywordSearches {
            guard let matches = try? await adaptiveKakaoSearch(
                service,
                kind: .keyword(search.query),
                in: rectangle,
                origin: origin
            ) else { continue }

            merge(matches, taggedAs: search.tag, into: &collected)
        }

        return collected
    }

    private enum KakaoSearchKind: Sendable {
        case category
        case keyword(String)
    }

    private struct SearchTile: Sendable {
        let rectangle: KakaoSearchRectangle
        let depth: Int
    }

    /// 포화된 타일만 재귀적으로 네 등분합니다. 한 단계에서 최대 여섯 타일만 동시에 보내
    /// 빠르게 찾되 순간 호출량이 과도해지지 않게 합니다.
    private func adaptiveKakaoSearch(
        _ service: KakaoLocalService,
        kind: KakaoSearchKind,
        in rectangle: KakaoSearchRectangle,
        origin: CLLocationCoordinate2D
    ) async throws -> [Cafe] {
        let maximumDepth = 8
        let minimumTileSideMeters: CLLocationDistance = 80
        let concurrency = 6

        var pending = [SearchTile(rectangle: rectangle, depth: 0)]
        var collected: [Cafe] = []

        while !pending.isEmpty {
            var next: [SearchTile] = []

            for start in stride(from: 0, to: pending.count, by: concurrency) {
                let end = min(start + concurrency, pending.count)
                let chunk = Array(pending[start..<end])

                let batches = try await withThrowingTaskGroup(
                    of: (SearchTile, KakaoCafeBatch).self
                ) { group in
                    for tile in chunk {
                        group.addTask {
                            let batch = switch kind {
                            case .category:
                                try await service.categoryCafeBatch(
                                    in: tile.rectangle,
                                    origin: origin
                                )
                            case .keyword(let query):
                                try await service.searchCafeBatch(
                                    query: query,
                                    in: tile.rectangle,
                                    origin: origin
                                )
                            }
                            return (tile, batch)
                        }
                    }

                    var values: [(SearchTile, KakaoCafeBatch)] = []
                    for try await value in group { values.append(value) }
                    return values
                }

                for (tile, batch) in batches {
                    let shouldSplit = batch.isSaturated
                        && tile.depth < maximumDepth
                        && Self.longestSideMeters(of: tile.rectangle) > minimumTileSideMeters

                    if shouldSplit {
                        next.append(contentsOf: Self.quarters(of: tile.rectangle).map {
                            SearchTile(rectangle: $0, depth: tile.depth + 1)
                        })
                    } else {
                        collected.append(contentsOf: batch.cafes)
                    }
                }
            }

            pending = next
        }

        return dedupe(collected)
    }

    /// 키워드 하나가 잡아낸 카페에는 그 키워드의 유형만 붙입니다. 여러 유형을 켰다고
    /// 베이커리 검색 결과에 분위기 태그까지 한꺼번에 붙이면 AND 필터가 무의미해집니다.
    private func merge(_ matches: [Cafe], taggedAs tag: CafeTag, into collected: inout [Cafe]) {
        var indexByID = Dictionary(uniqueKeysWithValues: collected.indices.map { (collected[$0].id, $0) })
        var indexByPin = Dictionary(uniqueKeysWithValues: collected.indices.map { (collected[$0].dedupeKey, $0) })

        for cafe in matches {
            if let index = indexByID[cafe.id] ?? indexByPin[cafe.dedupeKey] {
                collected[index].tags.insert(tag)
            } else {
                var tagged = cafe
                tagged.tags.insert(tag)
                indexByID[tagged.id] = collected.count
                indexByPin[tagged.dedupeKey] = collected.count
                collected.append(tagged)
            }
        }
    }

    /// 해외 검색과 국내 대체 검색은 Apple 결과를 여러 원으로 나눠 합칩니다.
    private func fetchFromApple(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) async -> [Cafe] {
        let samples = Self.samplePoints(center: center, radiusMeters: radiusMeters)
        let resolver = appleResolver

        return await withTaskGroup(of: [Cafe].self) { group in
            for sample in samples {
                group.addTask {
                    await resolver.nearbyCafes(
                        around: sample.center,
                        radiusMeters: sample.radiusMeters
                    )
                }
            }

            var all: [Cafe] = []
            for await result in group { all.append(contentsOf: result) }
            return all
        }
    }

    private static func searchRectangle(
        center: CLLocationCoordinate2D,
        radiusMeters: CLLocationDistance
    ) -> KakaoSearchRectangle {
        let latitudeDelta = radiusMeters / 111_000
        let longitudeScale = max(0.1, cos(center.latitude * .pi / 180))
        let longitudeDelta = radiusMeters / (111_000 * longitudeScale)

        return KakaoSearchRectangle(
            west: center.longitude - longitudeDelta,
            south: center.latitude - latitudeDelta,
            east: center.longitude + longitudeDelta,
            north: center.latitude + latitudeDelta
        )
    }

    private static func quarters(of rectangle: KakaoSearchRectangle) -> [KakaoSearchRectangle] {
        let middleLongitude = (rectangle.west + rectangle.east) / 2
        let middleLatitude = (rectangle.south + rectangle.north) / 2

        return [
            KakaoSearchRectangle(west: rectangle.west, south: rectangle.south, east: middleLongitude, north: middleLatitude),
            KakaoSearchRectangle(west: middleLongitude, south: rectangle.south, east: rectangle.east, north: middleLatitude),
            KakaoSearchRectangle(west: rectangle.west, south: middleLatitude, east: middleLongitude, north: rectangle.north),
            KakaoSearchRectangle(west: middleLongitude, south: middleLatitude, east: rectangle.east, north: rectangle.north)
        ]
    }

    private static func longestSideMeters(of rectangle: KakaoSearchRectangle) -> CLLocationDistance {
        let latitude = (rectangle.south + rectangle.north) / 2
        let height = (rectangle.north - rectangle.south) * 111_000
        let width = (rectangle.east - rectangle.west) * 111_000
            * max(0.1, cos(latitude * .pi / 180))
        return max(height, width)
    }

    private func dedupe(_ cafes: [Cafe]) -> [Cafe] {
        var seenIDs = Set<String>()
        var seenPins = Set<String>()
        return cafes.filter { cafe in
            seenIDs.insert(cafe.id).inserted && seenPins.insert(cafe.dedupeKey).inserted
        }
    }

    // MARK: - 결과 반영

    /// 받아 온 카페를 기준점에 맞춰 정리해 넣습니다.
    private func apply(_ fetched: [Cafe], origin: CLLocationCoordinate2D) {
        searchOrigin = origin
        fetchedCafes = fetched
            .map { $0.relative(to: origin) }
            .sorted { $0.distanceMeters < $1.distanceMeters }
        lastFetchLocation = origin
        lastFetchTagKey = currentTagKey

        // 새 목록에 같은 카페가 있으면 거리·방위가 갱신된 쪽으로 바꿔 끼웁니다.
        // 없으면 선택을 그대로 둡니다 — 목록 밖에서 고른 카페일 수 있습니다.
        let previousSelectionID = selectedCafe?.id
        applyFilter()
        if let previousSelectionID,
           let refreshed = cafes.first(where: { $0.id == previousSelectionID }) {
            selectedCafe = refreshed
        }
    }

    /// 서버를 다시 부르지 않고 거리·방위만 새 기준점으로 다시 잽니다.
    private func recomputeDistances(from origin: CLLocationCoordinate2D) {
        searchOrigin = origin
        let selectedID = selectedCafe?.id
        fetchedCafes = fetchedCafes.map { $0.relative(to: origin) }
        applyFilter()
        if let selectedID, let refreshed = cafes.first(where: { $0.id == selectedID }) {
            selectedCafe = refreshed
        }
    }

    private var currentTagKey: String {
        activeTags.map(\.rawValue).sorted().joined(separator: ",")
    }

    private func beginSearch() -> Int {
        searchRevision += 1
        return searchRevision
    }

    // MARK: - 검색

    /// 사용자가 직접 입력한 검색어. 국내면 Kakao, 해외면 Apple MapKit으로 찾습니다.
    func search(query: String, around origin: CLLocationCoordinate2D) async -> [Cafe] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let territory = await territoryResolver.territory(at: origin)
        if territory == .international {
            dataSource = .appleInternational
            errorMessage = nil
            return await appleResolver.search(
                query: trimmed,
                around: origin,
                radiusMeters: 10_000
            )
        }

        if let kakao = KakaoLocalService() {
            do {
                let results = try await kakao.searchCafes(
                    query: trimmed,
                    around: origin,
                    radiusMeters: 10_000
                )
                if !results.isEmpty {
                    dataSource = .kakao
                    errorMessage = nil
                    return results
                }
                dataSource = .appleFallback(reason: "Kakao 검색 결과 없음")
            } catch {
                let reason = (error as? KakaoLocalError)?.errorDescription ?? "Kakao 호출 실패"
                dataSource = .appleFallback(reason: reason)
            }
        } else {
            dataSource = .appleFallback(reason: "Kakao API 키 없음")
        }

        return await appleResolver.search(query: trimmed, around: origin, radiusMeters: 10_000)
    }

    // MARK: - 선택과 경로

    func select(_ cafe: Cafe, from location: CLLocationCoordinate2D) async {
        selectedCafe = cafe
        await updateRoute(from: location)
    }

    func updateRoute(from location: CLLocationCoordinate2D) async {
        guard let selectedCafe else {
            route = nil
            return
        }

        // 다른 지역을 구경하는 중에는 선택한 카페가 수백 km 밖일 수 있습니다.
        // 도보 경로를 물어봐야 실패만 하므로 아예 묻지 않습니다.
        guard GeoMath.distanceMeters(from: location, to: selectedCafe.coordinate)
            <= Self.walkableLimitMeters else {
            route = nil
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: location.latitude, longitude: location.longitude),
            address: nil
        )
        request.destination = selectedCafe.mapItem
        request.transportType = .walking

        route = try? await MKDirections(request: request).calculate().routes.first
    }

    // MARK: - 미리보기

    static var preview: CafeStore {
        let store = CafeStore()
        store.fetchedCafes = PreviewCafeFactory.cafes(around: .seoulCityHall)
        store.cafes = store.fetchedCafes
        return store
    }
}
