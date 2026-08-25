//
//  CafeModels.swift
//  CoFFMap
//
//  앱이 다루는 값은 카페 하나뿐입니다.
//
//  `source`가 중요합니다. Kakao Local API는 약관상 응답을 어떤 형태로도 저장할 수 없어서
//  (실시간 호출만 허용) 화면에 띄우는 용도로만 씁니다. 즐겨찾기처럼 저장이 필요한 순간에는
//  `AppleCafeResolver`가 같은 카페를 Apple 지도에서 다시 찾아 `.apple` 카페로 바꿔 줍니다.
//  저장 경로에는 `.apple`만 들어가야 합니다 — `SavedCafeStore`가 이를 강제합니다.
//

import CoreLocation
import Foundation
import MapKit

struct Cafe: Identifiable, Hashable, Codable {
    enum Source: String, Codable, Sendable {
        /// Kakao Local API 실시간 응답. 저장 금지.
        case kakao
        /// Apple MapKit(MKLocalSearch). 저장 가능.
        case apple
        /// Xcode 미리보기용 가짜 값.
        case preview
    }

    let id: String
    let name: String
    /// 지번 주소.
    let address: String
    /// 도로명 주소. Kakao는 둘 다 주지만 Apple은 하나만 주는 경우가 있습니다.
    let roadAddress: String?
    let phone: String?
    /// Kakao의 "음식점 > 카페 > 커피전문점 > 스타벅스" 형태 분류. 태그 판정의 주요 단서입니다.
    let categoryName: String?
    /// 카카오맵 상세 페이지. 사용자가 리뷰·사진을 보고 싶을 때 여는 링크입니다.
    let placeURL: URL?
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let bearingDegrees: Double
    var tags: Set<CafeTag>
    let source: Source

    init(
        id: String,
        name: String,
        address: String,
        roadAddress: String? = nil,
        phone: String? = nil,
        categoryName: String? = nil,
        placeURL: URL? = nil,
        coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double,
        tags: Set<CafeTag> = [],
        source: Source
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.roadAddress = roadAddress
        self.phone = phone
        self.categoryName = categoryName
        self.placeURL = placeURL
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.bearingDegrees = bearingDegrees
        self.tags = tags
        self.source = source
    }

    /// 목록 한 줄에 넣을 짧은 주소. 도로명이 있으면 그쪽이 읽기 좋습니다.
    var displayAddress: String {
        let candidate = roadAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let candidate, !candidate.isEmpty { return candidate }
        return address.isEmpty ? "주소 정보 없음" : address
    }

    /// 칩에 쓸 태그를 정해진 순서로 정렬해 돌려줍니다.
    var orderedTags: [CafeTag] {
        CafeTag.displayOrder.filter { tags.contains($0) }
    }

    /// 이름 아래 한 줄로 붙는 짧은 설명. Live Activity와 길안내 화면에서 씁니다.
    /// 대표 태그가 있으면 그걸 쓰고, 없으면 그냥 "카페"입니다.
    var tagline: String {
        orderedTags.first?.title ?? "카페"
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = name
        return item
    }

    /// 같은 카페를 Kakao와 Apple 양쪽에서 받았을 때 겹치는지 판단하는 키.
    /// 두 서비스의 좌표가 몇 미터씩 어긋나므로 약 10m 격자로 뭉갭니다.
    var dedupeKey: String {
        let normalizedName = name
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        return "\(normalizedName)|\(Int(coordinate.latitude * 10000))|\(Int(coordinate.longitude * 10000))"
    }

    /// 사용자가 움직였을 때 서버를 다시 부르지 않고 거리·방위만 현 위치 기준으로 갱신합니다.
    func relative(to origin: CLLocationCoordinate2D) -> Cafe {
        Cafe(
            id: id,
            name: name,
            address: address,
            roadAddress: roadAddress,
            phone: phone,
            categoryName: categoryName,
            placeURL: placeURL,
            coordinate: coordinate,
            distanceMeters: GeoMath.distanceMeters(from: origin, to: coordinate),
            bearingDegrees: GeoMath.bearingDegrees(from: origin, to: coordinate),
            tags: tags,
            source: source
        )
    }
}

// MARK: - Codable

extension Cafe {
    enum CodingKeys: String, CodingKey {
        case id, name, address, roadAddress, phone, categoryName, placeURL
        case latitude, longitude, distanceMeters, bearingDegrees, tags, source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)
        roadAddress = try container.decodeIfPresent(String.self, forKey: .roadAddress)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        placeURL = try container.decodeIfPresent(URL.self, forKey: .placeURL)
        coordinate = CLLocationCoordinate2D(
            latitude: try container.decode(CLLocationDegrees.self, forKey: .latitude),
            longitude: try container.decode(CLLocationDegrees.self, forKey: .longitude)
        )
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
        bearingDegrees = try container.decodeIfPresent(Double.self, forKey: .bearingDegrees) ?? 0
        tags = Set(try container.decodeIfPresent([CafeTag].self, forKey: .tags) ?? [])
        // 예전에 저장된 값에는 source가 없습니다. 저장돼 있었다는 건 Apple 데이터라는 뜻입니다.
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .apple
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(roadAddress, forKey: .roadAddress)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(categoryName, forKey: .categoryName)
        try container.encodeIfPresent(placeURL, forKey: .placeURL)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(bearingDegrees, forKey: .bearingDegrees)
        try container.encode(Array(tags), forKey: .tags)
        try container.encode(source, forKey: .source)
    }
}

// MARK: - Hashable

/// 거리·방위는 위치가 바뀔 때마다 갱신되므로 동일성 판단에서 뺍니다.
/// 그렇지 않으면 걸을 때마다 선택 상태와 Set 멤버십이 깨집니다.
extension Cafe {
    static func == (lhs: Cafe, rhs: Cafe) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 좌표 보조

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

extension CLLocationCoordinate2D: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }
}

extension CLLocationCoordinate2D {
    /// 위치 권한이 없을 때 보여 줄 기준점.
    static let seoulCityHall = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
}
