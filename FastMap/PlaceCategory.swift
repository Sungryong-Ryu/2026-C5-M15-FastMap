//
//  PlaceCategory.swift
//  FastMap
//
//  카테고리는 더 이상 고정된 enum이 아니라 사용자가 추가/수정/정렬할 수 있는 값입니다.
//  기본 8종은 `PlaceCategory.builtInDefaults`로 제공되고, 사용자가 만든 카테고리는
//  `CategoryIntelligence`가 이름을 분석해 검색어·POI 타입·아이콘·색을 채워줍니다.
//

import Foundation
import MapKit
import SwiftUI
import UIKit

struct PlaceCategory: Identifiable, Codable, Sendable {
    /// 안정적인 식별자. 기본 카테고리는 예전 enum rawValue를 그대로 씁니다.
    var id: String
    var title: String
    var symbolName: String
    var colorID: String
    /// MKLocalSearch 자연어 검색에 쓰이는 문구.
    var searchQuery: String
    /// MKPointOfInterestCategory rawValue 목록. 비어 있으면 자연어 검색만 사용합니다.
    var poiRawValues: [String]
    /// 앱이 기본 제공한 카테고리인지 여부. 삭제 대신 "기본값으로 되돌리기"가 제공됩니다.
    var isBuiltIn: Bool
    /// 칩 목록에서 숨김 처리.
    var isHidden: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        symbolName: String = "mappin.circle.fill",
        colorID: String = CategoryPalette.fallbackID,
        searchQuery: String? = nil,
        poiRawValues: [String] = [],
        isBuiltIn: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.colorID = colorID
        self.searchQuery = searchQuery ?? title
        self.poiRawValues = poiRawValues
        self.isBuiltIn = isBuiltIn
        self.isHidden = isHidden
    }

    var tint: Color { CategoryPalette.color(for: colorID) }

    var pointOfInterestCategories: [MKPointOfInterestCategory]? {
        guard !poiRawValues.isEmpty else { return nil }
        return poiRawValues.map(MKPointOfInterestCategory.init(rawValue:))
    }
}

// MARK: - Identity

/// 카테고리는 사용자가 이름·아이콘·색을 바꿀 수 있으므로 동일성은 id로만 판단합니다.
/// 이렇게 해야 편집 중에도 선택 상태나 Set 멤버십이 유지됩니다.
extension PlaceCategory: Hashable {
    static func == (lhs: PlaceCategory, rhs: PlaceCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Codable (레거시 호환)

extension PlaceCategory {
    private enum CodingKeys: String, CodingKey {
        case id, title, symbolName, colorID, searchQuery, poiRawValues, isBuiltIn, isHidden
    }

    init(from decoder: Decoder) throws {
        // 예전 버전은 카테고리를 enum rawValue 문자열 하나로 저장했습니다.
        if let single = try? decoder.singleValueContainer(),
           let legacyID = try? single.decode(String.self) {
            self = PlaceCategory.builtIn(id: legacyID)
                ?? PlaceCategory(id: legacyID, title: legacyID)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "mappin.circle.fill"
        colorID = try container.decodeIfPresent(String.self, forKey: .colorID) ?? CategoryPalette.fallbackID
        searchQuery = try container.decodeIfPresent(String.self, forKey: .searchQuery) ?? title
        poiRawValues = try container.decodeIfPresent([String].self, forKey: .poiRawValues) ?? []
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }
}

// MARK: - Built-ins

extension PlaceCategory {
    static let searchResult = PlaceCategory(
        id: "searchResult",
        title: "검색 결과",
        symbolName: "mappin.circle.fill",
        colorID: "violet",
        searchQuery: "검색",
        isBuiltIn: true
    )

    static let restroom = PlaceCategory(
        id: "restroom",
        title: "화장실",
        symbolName: "toilet.fill",
        colorID: "teal",
        searchQuery: "화장실",
        poiRawValues: [MKPointOfInterestCategory.restroom.rawValue],
        isBuiltIn: true
    )

    static let cafe = PlaceCategory(
        id: "cafe",
        title: "카페",
        symbolName: "cup.and.saucer.fill",
        colorID: "brown",
        searchQuery: "카페",
        poiRawValues: [MKPointOfInterestCategory.cafe.rawValue],
        isBuiltIn: true
    )

    static let bank = PlaceCategory(
        id: "bank",
        title: "은행",
        symbolName: "building.columns.fill",
        colorID: "navy",
        searchQuery: "은행",
        poiRawValues: [MKPointOfInterestCategory.bank.rawValue, MKPointOfInterestCategory.atm.rawValue],
        isBuiltIn: true
    )

    static let hospital = PlaceCategory(
        id: "hospital",
        title: "병원",
        symbolName: "cross.fill",
        colorID: "pink",
        searchQuery: "병원",
        poiRawValues: [MKPointOfInterestCategory.hospital.rawValue],
        isBuiltIn: true
    )

    static let restaurant = PlaceCategory(
        id: "restaurant",
        title: "음식점",
        symbolName: "fork.knife",
        colorID: "green",
        searchQuery: "음식점",
        poiRawValues: [MKPointOfInterestCategory.restaurant.rawValue],
        isBuiltIn: true
    )

    static let pharmacy = PlaceCategory(
        id: "pharmacy",
        title: "약국",
        symbolName: "cross.case.fill",
        colorID: "red",
        searchQuery: "약국",
        poiRawValues: [MKPointOfInterestCategory.pharmacy.rawValue],
        isBuiltIn: true
    )

    static let convenienceStore = PlaceCategory(
        id: "convenienceStore",
        title: "편의점",
        symbolName: "basket.fill",
        colorID: "orange",
        searchQuery: "편의점",
        poiRawValues: [MKPointOfInterestCategory.store.rawValue, MKPointOfInterestCategory.foodMarket.rawValue],
        isBuiltIn: true
    )

    static let parking = PlaceCategory(
        id: "parking",
        title: "주차장",
        symbolName: "parkingsign",
        colorID: "blue",
        searchQuery: "주차장",
        poiRawValues: [MKPointOfInterestCategory.parking.rawValue],
        isBuiltIn: true
    )

    /// 앱 최초 실행 시 제공되는 기본 카테고리 순서.
    static let builtInDefaults: [PlaceCategory] = [
        .restroom, .cafe, .bank, .hospital, .restaurant, .pharmacy, .convenienceStore, .parking
    ]

    static func builtIn(id: String) -> PlaceCategory? {
        if id == searchResult.id { return searchResult }
        return builtInDefaults.first { $0.id == id }
    }

    /// 미리보기/폴백용.
    static var quickCategories: [PlaceCategory] { builtInDefaults }
}

// MARK: - 아이콘 카탈로그

/// 사용자가 카테고리 아이콘을 고를 수 있도록 정리한 SF Symbols 목록.
enum CategorySymbolCatalog {
    struct Group: Identifiable {
        let id: String
        let title: String
        let symbols: [String]
    }

    static let groups: [Group] = [
        Group(id: "food", title: "음식 · 카페", symbols: [
            "fork.knife", "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill",
            "birthday.cake.fill", "carrot.fill", "fish.fill", "wineglass.fill", "waterbottle.fill",
            "popcorn.fill", "frying.pan.fill"
        ]),
        Group(id: "shopping", title: "쇼핑 · 생활", symbols: [
            "basket.fill", "cart.fill", "bag.fill", "storefront.fill", "creditcard.fill",
            "gift.fill", "shippingbox.fill", "tag.fill", "handbag.fill", "washer.fill",
            "scissors", "hammer.fill"
        ]),
        Group(id: "health", title: "건강 · 의료", symbols: [
            "cross.fill", "cross.case.fill", "stethoscope", "pills.fill", "heart.fill",
            "bandage.fill", "eye.fill", "lungs.fill", "figure.run", "dumbbell.fill", "leaf.fill"
        ]),
        Group(id: "transport", title: "이동 · 교통", symbols: [
            "parkingsign", "car.fill", "bus.fill", "tram.fill", "bicycle", "scooter",
            "airplane", "ferry.fill", "fuelpump.fill", "ev.charger.fill", "figure.walk"
        ]),
        Group(id: "public", title: "공공 · 금융", symbols: [
            "building.columns.fill", "banknote.fill", "envelope.fill", "books.vertical.fill",
            "graduationcap.fill", "building.2.fill", "shield.lefthalf.filled", "flame.fill",
            "phone.fill", "printer.fill", "trash.fill"
        ]),
        Group(id: "leisure", title: "여가 · 문화", symbols: [
            "film.fill", "music.note", "gamecontroller.fill", "theatermasks.fill", "camera.fill",
            "paintpalette.fill", "sportscourt.fill", "tent.fill", "tree.fill", "mountain.2.fill",
            "sun.max.fill", "pawprint.fill"
        ]),
        Group(id: "basic", title: "기본", symbols: [
            "toilet.fill", "mappin.circle.fill", "star.fill", "bookmark.fill", "flag.fill",
            "house.fill", "bed.double.fill", "wifi", "key.fill", "questionmark.circle.fill",
            "sparkles", "circle.grid.2x2.fill"
        ])
    ]

    static let all: [String] = groups.flatMap(\.symbols)

    /// 존재하지 않는 심볼 이름이 들어오면 안전한 기본값으로 바꿉니다.
    static func validated(_ symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "mappin.circle.fill" }
        if UIImage(systemName: trimmed) != nil { return trimmed }
        return "mappin.circle.fill"
    }
}
