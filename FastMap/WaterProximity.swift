//
//  WaterProximity.swift
//  CoFFMap
//
//  "강변·바다뷰" 태그를 좌표만으로 판정합니다.
//
//  왜 데이터를 직접 들고 있나:
//  Kakao Local API도 Apple MapKit도 "이 장소가 물가인가"를 알려주지 않습니다.
//  CLGeocoder의 `ocean`/`inlandWater`는 좌표가 물 **안**에 있을 때만 채워지고 호출 제한도
//  빡빡해서, 카페 40곳을 매번 물어볼 수 없습니다. 그래서 판정 기준을 앱이 직접 들고 갑니다.
//
//  두 가지 형태만 씁니다.
//  - `river`: 강 중심선을 꺾은선으로 두고, 중심선에서 (강 반폭 + 여유 거리) 안이면 강변.
//  - `coast`: 바다뷰 카페가 몰려 있는 해안 지역을 원으로 둡니다.
//
//  해안선 전체를 정밀하게 담으면 앱이 무거워지기만 하고 정확도는 별로 안 오릅니다.
//  실제로 사람들이 "바다 보러 가는" 지역만 넣는 편이 결과가 낫습니다.
//  빠진 곳이 있으면 `coastalSpots`에 한 줄 추가하면 됩니다.
//

import CoreLocation
import Foundation

enum WaterProximity {

    // MARK: - 판정

    /// 이 좌표가 강변이나 바닷가로 볼 만한 자리인지.
    static func isWaterfront(_ coordinate: CLLocationCoordinate2D) -> Bool {
        nearestWater(coordinate) != nil
    }

    /// 가장 가까운 물의 이름. 상세 화면에 "한강 근처" 같이 쓸 수 있습니다.
    static func nearestWater(_ coordinate: CLLocationCoordinate2D) -> String? {
        for spot in coastalSpots {
            let distance = GeoMath.distanceMeters(from: coordinate, to: spot.center)
            if distance <= spot.radiusMeters { return spot.name }
        }

        for river in rivers {
            let distance = distanceToPolyline(coordinate, river.centerline)
            if distance <= river.halfWidthMeters + river.bankBandMeters { return river.name }
        }

        return nil
    }

    // MARK: - 강

    struct River {
        let name: String
        /// 강 중심선. 상류에서 하류 방향으로 이어 둡니다.
        let centerline: [CLLocationCoordinate2D]
        /// 중심선에서 물가까지의 거리. 강 폭의 절반입니다.
        let halfWidthMeters: CLLocationDistance
        /// 물가에서 얼마나 안쪽까지 "강변"으로 볼지.
        let bankBandMeters: CLLocationDistance
    }

    static let rivers: [River] = [
        River(
            name: "한강",
            centerline: [
                .init(latitude: 37.5820, longitude: 126.7700),
                .init(latitude: 37.5890, longitude: 126.8090),
                .init(latitude: 37.5780, longitude: 126.8300),
                .init(latitude: 37.5680, longitude: 126.8600),
                .init(latitude: 37.5550, longitude: 126.8900),
                .init(latitude: 37.5400, longitude: 126.9200),
                .init(latitude: 37.5230, longitude: 126.9350),
                .init(latitude: 37.5170, longitude: 126.9600),
                .init(latitude: 37.5150, longitude: 126.9900),
                .init(latitude: 37.5250, longitude: 127.0200),
                .init(latitude: 37.5300, longitude: 127.0600),
                .init(latitude: 37.5400, longitude: 127.1000),
                .init(latitude: 37.5550, longitude: 127.1300),
                .init(latitude: 37.5700, longitude: 127.1600)
            ],
            halfWidthMeters: 550,
            bankBandMeters: 400
        ),
        River(
            name: "북한강",
            centerline: [
                .init(latitude: 37.8300, longitude: 127.5100),
                .init(latitude: 37.7300, longitude: 127.4900),
                .init(latitude: 37.6400, longitude: 127.4200),
                .init(latitude: 37.5500, longitude: 127.3200),
                .init(latitude: 37.5400, longitude: 127.2900)
            ],
            halfWidthMeters: 400,
            bankBandMeters: 400
        ),
        River(
            name: "낙동강",
            centerline: [
                .init(latitude: 35.3300, longitude: 128.9300),
                .init(latitude: 35.2600, longitude: 128.9600),
                .init(latitude: 35.2000, longitude: 128.9700),
                .init(latitude: 35.1500, longitude: 128.9600),
                .init(latitude: 35.1000, longitude: 128.9500),
                .init(latitude: 35.0700, longitude: 128.9400)
            ],
            halfWidthMeters: 500,
            bankBandMeters: 400
        ),
        River(
            name: "금강",
            centerline: [
                .init(latitude: 36.4700, longitude: 127.2600),
                .init(latitude: 36.5300, longitude: 127.2100),
                .init(latitude: 36.5900, longitude: 127.0700),
                .init(latitude: 36.4600, longitude: 126.9200),
                .init(latitude: 36.0000, longitude: 126.7000)
            ],
            halfWidthMeters: 350,
            bankBandMeters: 350
        ),
        River(
            name: "영산강",
            centerline: [
                .init(latitude: 35.1600, longitude: 126.8400),
                .init(latitude: 35.0300, longitude: 126.7300),
                .init(latitude: 34.9000, longitude: 126.6100),
                .init(latitude: 34.8000, longitude: 126.4300)
            ],
            halfWidthMeters: 300,
            bankBandMeters: 350
        )
    ]

    // MARK: - 바다

    struct CoastalSpot {
        let name: String
        let center: CLLocationCoordinate2D
        let radiusMeters: CLLocationDistance
    }

    static let coastalSpots: [CoastalSpot] = [
        // 부산·울산
        .init(name: "해운대", center: .init(latitude: 35.1587, longitude: 129.1604), radiusMeters: 1800),
        .init(name: "광안리", center: .init(latitude: 35.1531, longitude: 129.1186), radiusMeters: 1500),
        .init(name: "송정", center: .init(latitude: 35.1786, longitude: 129.1994), radiusMeters: 1500),
        .init(name: "기장", center: .init(latitude: 35.2450, longitude: 129.2230), radiusMeters: 3000),
        .init(name: "다대포", center: .init(latitude: 35.0442, longitude: 128.9666), radiusMeters: 1500),
        .init(name: "영도 흰여울", center: .init(latitude: 35.0780, longitude: 129.0430), radiusMeters: 1500),
        .init(name: "울산 진하", center: .init(latitude: 35.3800, longitude: 129.3500), radiusMeters: 2500),

        // 동해안
        .init(name: "강릉 안목", center: .init(latitude: 37.7735, longitude: 128.9470), radiusMeters: 2500),
        .init(name: "경포", center: .init(latitude: 37.7955, longitude: 128.9080), radiusMeters: 2000),
        .init(name: "속초", center: .init(latitude: 38.1900, longitude: 128.6000), radiusMeters: 3000),
        .init(name: "양양", center: .init(latitude: 38.0200, longitude: 128.6700), radiusMeters: 3000),
        .init(name: "동해 묵호", center: .init(latitude: 37.5500, longitude: 129.1200), radiusMeters: 2500),
        .init(name: "포항 영일대", center: .init(latitude: 36.0600, longitude: 129.3900), radiusMeters: 2500),
        .init(name: "호미곶", center: .init(latitude: 36.0760, longitude: 129.5660), radiusMeters: 2500),

        // 서해안
        .init(name: "을왕리", center: .init(latitude: 37.4470, longitude: 126.3730), radiusMeters: 2500),
        .init(name: "영종도", center: .init(latitude: 37.4900, longitude: 126.4300), radiusMeters: 3000),
        .init(name: "강화", center: .init(latitude: 37.6900, longitude: 126.3500), radiusMeters: 4000),
        .init(name: "대부도", center: .init(latitude: 37.2600, longitude: 126.5800), radiusMeters: 4000),
        .init(name: "오이도", center: .init(latitude: 37.3450, longitude: 126.6900), radiusMeters: 2000),
        .init(name: "만리포", center: .init(latitude: 36.7900, longitude: 126.1400), radiusMeters: 3000),
        .init(name: "대천", center: .init(latitude: 36.3200, longitude: 126.5100), radiusMeters: 3000),
        .init(name: "선유도", center: .init(latitude: 35.8100, longitude: 126.4200), radiusMeters: 3000),

        // 남해안
        .init(name: "여수", center: .init(latitude: 34.7400, longitude: 127.7400), radiusMeters: 3500),
        .init(name: "통영", center: .init(latitude: 34.8450, longitude: 128.4200), radiusMeters: 3000),
        .init(name: "거제", center: .init(latitude: 34.8800, longitude: 128.6200), radiusMeters: 4000),
        .init(name: "남해", center: .init(latitude: 34.8300, longitude: 127.9000), radiusMeters: 5000),
        .init(name: "목포", center: .init(latitude: 34.7800, longitude: 126.3700), radiusMeters: 3000),

        // 제주
        .init(name: "제주 애월", center: .init(latitude: 33.4630, longitude: 126.3100), radiusMeters: 4000),
        .init(name: "제주 협재", center: .init(latitude: 33.3940, longitude: 126.2400), radiusMeters: 3000),
        .init(name: "제주 월정리", center: .init(latitude: 33.5560, longitude: 126.7960), radiusMeters: 3000),
        .init(name: "제주 성산", center: .init(latitude: 33.4600, longitude: 126.9300), radiusMeters: 3500),
        .init(name: "서귀포", center: .init(latitude: 33.2450, longitude: 126.5600), radiusMeters: 4000)
    ]

    // MARK: - 거리 계산

    /// 점에서 꺾은선까지의 최단 거리(m).
    private static func distanceToPolyline(
        _ point: CLLocationCoordinate2D,
        _ line: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard line.count > 1 else {
            return line.first.map { GeoMath.distanceMeters(from: point, to: $0) } ?? .greatestFiniteMagnitude
        }

        var shortest = CLLocationDistance.greatestFiniteMagnitude
        for index in 0..<(line.count - 1) {
            shortest = min(shortest, distanceToSegment(point, line[index], line[index + 1]))
        }
        return shortest
    }

    /// 점에서 선분까지의 거리. 몇 km 범위에서는 평면으로 봐도 오차가 무시할 만합니다.
    private static func distanceToSegment(
        _ point: CLLocationCoordinate2D,
        _ start: CLLocationCoordinate2D,
        _ end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        // 위도 1도는 어디서나 약 111km, 경도 1도는 위도에 따라 줄어듭니다.
        let metersPerDegreeLatitude = 111_320.0
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(point.latitude * .pi / 180)

        let px = point.longitude * metersPerDegreeLongitude
        let py = point.latitude * metersPerDegreeLatitude
        let ax = start.longitude * metersPerDegreeLongitude
        let ay = start.latitude * metersPerDegreeLatitude
        let bx = end.longitude * metersPerDegreeLongitude
        let by = end.latitude * metersPerDegreeLatitude

        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(px - ax, py - ay) }

        // 점을 선분 위에 투영한 위치. 0~1 밖이면 선분 끝으로 잘라 냅니다.
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lengthSquared))
        return hypot(px - (ax + t * dx), py - (ay + t * dy))
    }
}
