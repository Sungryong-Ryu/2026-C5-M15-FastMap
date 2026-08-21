//
//  CategoryIntelligence.swift
//  FastMap
//
//  사용자가 입력한 카테고리 이름을 분석해서 지도 검색에 필요한 값들을 채워 줍니다.
//
//  1순위: Apple Intelligence (FoundationModels) 온디바이스 모델로 추론
//  2순위: 한국어/영어 키워드 매칭 테이블 + 자연어 검색
//
//  두 경로 모두 결과를 화이트리스트로 검증하기 때문에, 모델이 이상한 값을 주더라도
//  앱에서 실제로 쓸 수 있는 값만 남습니다.
//

import Combine
import Foundation
import FoundationModels
import MapKit

// MARK: - 결과 모델

struct CategorySuggestion: Equatable, Sendable {
    enum Source: String, Sendable {
        case appleIntelligence
        case keyword

        var label: String {
            switch self {
            case .appleIntelligence: "Apple Intelligence 분석"
            case .keyword: "키워드 분석"
            }
        }
    }

    var searchQuery: String
    var poiRawValues: [String]
    var symbolName: String
    var colorID: String
    var source: Source

    /// 사용자가 확인할 수 있는 한 줄 설명.
    var explanation: String {
        if poiRawValues.isEmpty {
            return "\(source.label) · ‘\(searchQuery)’ 로 주변을 검색해요"
        }
        let names = poiRawValues.compactMap(POICatalog.displayName(forRawValue:))
        let joined = names.isEmpty ? "지도 분류" : names.joined(separator: ", ")
        return "\(source.label) · \(joined) 분류 + ‘\(searchQuery)’ 검색"
    }
}

// MARK: - POI 화이트리스트

/// 모델이나 키워드 테이블이 내놓은 값을 검증할 때 쓰는 Apple 지도 POI 분류 목록.
enum POICatalog {
    struct Entry: Identifiable, Hashable {
        /// 모델과 키워드 테이블이 사용하는 POI 키
        let id: String
        /// MKPointOfInterestCategory.rawValue
        let rawValue: String
        let korean: String
    }

    static let entries: [Entry] = [
        Entry(id: "airport", rawValue: MKPointOfInterestCategory.airport.rawValue, korean: "공항"),
        Entry(id: "amusementPark", rawValue: MKPointOfInterestCategory.amusementPark.rawValue, korean: "놀이공원"),
        Entry(id: "aquarium", rawValue: MKPointOfInterestCategory.aquarium.rawValue, korean: "아쿠아리움"),
        Entry(id: "atm", rawValue: MKPointOfInterestCategory.atm.rawValue, korean: "ATM"),
        Entry(id: "bakery", rawValue: MKPointOfInterestCategory.bakery.rawValue, korean: "베이커리"),
        Entry(id: "bank", rawValue: MKPointOfInterestCategory.bank.rawValue, korean: "은행"),
        Entry(id: "beach", rawValue: MKPointOfInterestCategory.beach.rawValue, korean: "해변"),
        Entry(id: "brewery", rawValue: MKPointOfInterestCategory.brewery.rawValue, korean: "양조장"),
        Entry(id: "cafe", rawValue: MKPointOfInterestCategory.cafe.rawValue, korean: "카페"),
        Entry(id: "campground", rawValue: MKPointOfInterestCategory.campground.rawValue, korean: "캠핑장"),
        Entry(id: "carRental", rawValue: MKPointOfInterestCategory.carRental.rawValue, korean: "렌터카"),
        Entry(id: "evCharger", rawValue: MKPointOfInterestCategory.evCharger.rawValue, korean: "전기차 충전소"),
        Entry(id: "fireStation", rawValue: MKPointOfInterestCategory.fireStation.rawValue, korean: "소방서"),
        Entry(id: "fitnessCenter", rawValue: MKPointOfInterestCategory.fitnessCenter.rawValue, korean: "피트니스"),
        Entry(id: "foodMarket", rawValue: MKPointOfInterestCategory.foodMarket.rawValue, korean: "식료품점"),
        Entry(id: "gasStation", rawValue: MKPointOfInterestCategory.gasStation.rawValue, korean: "주유소"),
        Entry(id: "hospital", rawValue: MKPointOfInterestCategory.hospital.rawValue, korean: "병원"),
        Entry(id: "hotel", rawValue: MKPointOfInterestCategory.hotel.rawValue, korean: "숙소"),
        Entry(id: "laundry", rawValue: MKPointOfInterestCategory.laundry.rawValue, korean: "세탁소"),
        Entry(id: "library", rawValue: MKPointOfInterestCategory.library.rawValue, korean: "도서관"),
        Entry(id: "marina", rawValue: MKPointOfInterestCategory.marina.rawValue, korean: "마리나"),
        Entry(id: "movieTheater", rawValue: MKPointOfInterestCategory.movieTheater.rawValue, korean: "영화관"),
        Entry(id: "museum", rawValue: MKPointOfInterestCategory.museum.rawValue, korean: "박물관"),
        Entry(id: "nationalPark", rawValue: MKPointOfInterestCategory.nationalPark.rawValue, korean: "국립공원"),
        Entry(id: "nightlife", rawValue: MKPointOfInterestCategory.nightlife.rawValue, korean: "주점"),
        Entry(id: "park", rawValue: MKPointOfInterestCategory.park.rawValue, korean: "공원"),
        Entry(id: "parking", rawValue: MKPointOfInterestCategory.parking.rawValue, korean: "주차장"),
        Entry(id: "pharmacy", rawValue: MKPointOfInterestCategory.pharmacy.rawValue, korean: "약국"),
        Entry(id: "police", rawValue: MKPointOfInterestCategory.police.rawValue, korean: "경찰서"),
        Entry(id: "postOffice", rawValue: MKPointOfInterestCategory.postOffice.rawValue, korean: "우체국"),
        Entry(id: "publicTransport", rawValue: MKPointOfInterestCategory.publicTransport.rawValue, korean: "대중교통"),
        Entry(id: "restaurant", rawValue: MKPointOfInterestCategory.restaurant.rawValue, korean: "음식점"),
        Entry(id: "restroom", rawValue: MKPointOfInterestCategory.restroom.rawValue, korean: "화장실"),
        Entry(id: "school", rawValue: MKPointOfInterestCategory.school.rawValue, korean: "학교"),
        Entry(id: "stadium", rawValue: MKPointOfInterestCategory.stadium.rawValue, korean: "경기장"),
        Entry(id: "store", rawValue: MKPointOfInterestCategory.store.rawValue, korean: "상점"),
        Entry(id: "theater", rawValue: MKPointOfInterestCategory.theater.rawValue, korean: "공연장"),
        Entry(id: "university", rawValue: MKPointOfInterestCategory.university.rawValue, korean: "대학교"),
        Entry(id: "winery", rawValue: MKPointOfInterestCategory.winery.rawValue, korean: "와이너리"),
        Entry(id: "zoo", rawValue: MKPointOfInterestCategory.zoo.rawValue, korean: "동물원")
    ]

    static let allKeys: [String] = entries.map(\.id)

    static func rawValue(forKey key: String) -> String? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.first { $0.id.caseInsensitiveCompare(normalized) == .orderedSame }?.rawValue
    }

    static func displayName(forRawValue rawValue: String) -> String? {
        entries.first { $0.rawValue == rawValue }?.korean
    }

    /// 모델이 준 키 목록을 유효한 rawValue 배열로 정리합니다.
    static func sanitize(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        return keys.compactMap { rawValue(forKey: $0) }.filter { seen.insert($0).inserted }
    }
}

// MARK: - 분석기

@MainActor
final class CategoryIntelligence: ObservableObject {
    /// 이 기기에서 Apple Intelligence 분석을 쓸 수 있는지.
    var isAppleIntelligenceAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// 사용할 수 없을 때 사용자에게 보여줄 이유.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "이 기기는 Apple Intelligence를 지원하지 않아 키워드 분석을 사용해요."
            case .appleIntelligenceNotEnabled:
                return "설정에서 Apple Intelligence를 켜면 더 정확하게 분석할 수 있어요."
            case .modelNotReady:
                return "온디바이스 모델을 준비하는 중이라 지금은 키워드 분석을 사용해요."
            @unknown default:
                return "지금은 키워드 분석을 사용해요."
            }
        @unknown default:
            return nil
        }
    }

    /// 카테고리 이름을 분석합니다. 실패하면 항상 키워드 결과로 대체되므로 절대 실패하지 않습니다.
    func analyze(name rawName: String) async -> CategorySuggestion {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = KeywordCategoryAnalyzer.suggestion(for: name)
        guard !name.isEmpty else { return fallback }
        guard isAppleIntelligenceAvailable else { return fallback }

        do {
            let blueprint = try await requestBlueprint(for: name)
            return merged(blueprint: blueprint, name: name, fallback: fallback)
        } catch {
            return fallback
        }
    }

    // MARK: Apple Intelligence

    private func requestBlueprint(for name: String) async throws -> CategoryBlueprint {
        let session = LanguageModelSession {
            """
            너는 지도 앱의 장소 카테고리 분석기다.
            사용자가 만든 카테고리 이름을 받아서, Apple 지도(MapKit)에서 그 장소들을 찾는 데 필요한 값을 채운다.

            [searchQuery]
            MKLocalSearch 자연어 검색에 그대로 넣을 짧은 단어다.
            - 실제 지도에 등록된 "업종 이름"으로 바꿔 쓴다. 사용자가 쓴 말이 구어체거나 좁으면 더 일반적인 업종어로 바꾼다.
            - 사용자가 한국어로 입력했으면 한국어로 답한다.
            - 문장, 설명, 조사를 붙이지 않는다. 1~2단어.

            [poiKeys]
            아래 목록에 있는 키만 쓴다. 의미가 정확히 겹칠 때만 넣고, 애매하면 빈 배열을 반환한다.
            너무 넓은 분류(store 등)를 억지로 넣으면 엉뚱한 장소가 섞이므로 넣지 않는다.
            \(POICatalog.allKeys.joined(separator: ", "))

            [symbolName]
            아래 SF Symbols 목록 중 의미가 가장 가까운 하나. 목록 밖의 이름은 절대 쓰지 않는다.
            \(CategorySymbolCatalog.all.joined(separator: ", "))

            [colorID]
            아래 중 하나. 카테고리 성격에 어울리는 색을 고른다.
            \(CategoryPalette.options.map(\.id).joined(separator: ", "))

            [예시]
            이름 "코인 세탁방" → searchQuery "코인세탁", poiKeys ["laundry"], symbolName "washer.fill", colorID "teal"
            이름 "강아지 병원" → searchQuery "동물병원", poiKeys [], symbolName "pawprint.fill", colorID "brown"
            이름 "혼밥하기 좋은 곳" → searchQuery "식당", poiKeys ["restaurant"], symbolName "fork.knife", colorID "green"
            이름 "노트북 하기 좋은 카페" → searchQuery "카페", poiKeys ["cafe"], symbolName "cup.and.saucer.fill", colorID "brown"
            이름 "따릉이" → searchQuery "자전거 대여소", poiKeys [], symbolName "bicycle", colorID "lime"
            """
        }

        let response = try await session.respond(
            to: "카테고리 이름: \"\(name)\"",
            generating: CategoryBlueprint.self
        )
        return response.content
    }

    /// 모델 결과를 검증하고, 비어 있거나 잘못된 값은 키워드 결과로 채웁니다.
    private func merged(
        blueprint: CategoryBlueprint,
        name: String,
        fallback: CategorySuggestion
    ) -> CategorySuggestion {
        let query = blueprint.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let poi = POICatalog.sanitize(blueprint.poiKeys)
        let symbol = CategorySymbolCatalog.all.contains(blueprint.symbolName)
            ? blueprint.symbolName
            : CategorySymbolCatalog.validated(blueprint.symbolName)
        let color = CategoryPalette.contains(blueprint.colorID) ? blueprint.colorID : fallback.colorID

        return CategorySuggestion(
            searchQuery: query.isEmpty ? (fallback.searchQuery.isEmpty ? name : fallback.searchQuery) : query,
            poiRawValues: poi.isEmpty ? fallback.poiRawValues : poi,
            symbolName: symbol == "mappin.circle.fill" ? fallback.symbolName : symbol,
            colorID: color,
            source: .appleIntelligence
        )
    }
}

/// 온디바이스 모델이 채워 주는 구조.
@Generable
struct CategoryBlueprint {
    @Guide(description: "Apple 지도 자연어 검색에 넣을 짧은 검색어. 사용자가 쓴 언어를 유지한다.")
    var searchQuery: String

    @Guide(description: "허용된 POI 키만 담은 배열. 정확히 맞는 분류가 없으면 빈 배열.")
    var poiKeys: [String]

    @Guide(description: "허용된 SF Symbols 목록 중 하나.")
    var symbolName: String

    @Guide(description: "허용된 색상 id 중 하나.")
    var colorID: String
}

// MARK: - 키워드 폴백

/// Apple Intelligence를 못 쓰는 기기에서도 같은 결과 구조를 만들어 주는 규칙 기반 분석기.
enum KeywordCategoryAnalyzer {
    private struct Rule {
        let keywords: [String]
        let poiKeys: [String]
        let symbolName: String
        let colorID: String
        /// 검색어를 별도로 지정하고 싶을 때.
        var searchQuery: String? = nil
    }

    private static let rules: [Rule] = [
        Rule(keywords: ["화장실", "restroom", "toilet", "wc"], poiKeys: ["restroom"], symbolName: "toilet.fill", colorID: "teal"),
        Rule(keywords: ["카페", "커피", "coffee", "cafe", "스타벅스"], poiKeys: ["cafe"], symbolName: "cup.and.saucer.fill", colorID: "brown"),
        Rule(keywords: ["베이커리", "빵집", "제과", "bakery"], poiKeys: ["bakery"], symbolName: "birthday.cake.fill", colorID: "orange"),
        Rule(keywords: ["은행", "atm", "현금", "bank"], poiKeys: ["bank", "atm"], symbolName: "building.columns.fill", colorID: "navy"),
        Rule(keywords: ["병원", "의원", "클리닉", "치과", "안과", "hospital", "clinic"], poiKeys: ["hospital"], symbolName: "cross.fill", colorID: "pink"),
        Rule(keywords: ["약국", "pharmacy", "drugstore"], poiKeys: ["pharmacy"], symbolName: "cross.case.fill", colorID: "red"),
        Rule(keywords: ["편의점", "convenience", "cu", "gs25", "세븐일레븐"], poiKeys: ["store", "foodMarket"], symbolName: "basket.fill", colorID: "orange"),
        Rule(keywords: ["마트", "시장", "슈퍼", "식료품", "market", "grocery"], poiKeys: ["foodMarket"], symbolName: "cart.fill", colorID: "green"),
        Rule(keywords: ["주차", "parking"], poiKeys: ["parking"], symbolName: "parkingsign", colorID: "blue"),
        Rule(keywords: ["주유", "기름", "gas", "fuel"], poiKeys: ["gasStation"], symbolName: "fuelpump.fill", colorID: "red"),
        Rule(keywords: ["충전", "전기차", "ev", "charger", "테슬라"], poiKeys: ["evCharger"], symbolName: "ev.charger.fill", colorID: "lime"),
        Rule(keywords: ["음식", "식당", "맛집", "밥", "restaurant", "고기", "국수", "분식"], poiKeys: ["restaurant"], symbolName: "fork.knife", colorID: "green"),
        Rule(keywords: ["술", "바", "펍", "포차", "이자카야", "bar", "pub", "nightlife"], poiKeys: ["nightlife"], symbolName: "wineglass.fill", colorID: "violet"),
        Rule(keywords: ["도서관", "library"], poiKeys: ["library"], symbolName: "books.vertical.fill", colorID: "brown"),
        Rule(keywords: ["서점", "책방", "bookstore"], poiKeys: ["store"], symbolName: "books.vertical.fill", colorID: "brown", searchQuery: "서점"),
        Rule(keywords: ["영화", "cinema", "movie", "cgv", "메가박스"], poiKeys: ["movieTheater"], symbolName: "film.fill", colorID: "violet"),
        Rule(keywords: ["공연", "극장", "theater", "콘서트"], poiKeys: ["theater"], symbolName: "theatermasks.fill", colorID: "violet"),
        Rule(keywords: ["박물관", "미술관", "museum", "gallery"], poiKeys: ["museum"], symbolName: "paintpalette.fill", colorID: "navy"),
        Rule(keywords: ["공원", "산책", "park"], poiKeys: ["park"], symbolName: "tree.fill", colorID: "green"),
        Rule(keywords: ["헬스", "짐", "피트니스", "운동", "gym", "fitness", "요가", "필라테스"], poiKeys: ["fitnessCenter"], symbolName: "dumbbell.fill", colorID: "lime"),
        Rule(keywords: ["수영", "swimming", "pool"], poiKeys: ["fitnessCenter"], symbolName: "figure.run", colorID: "teal", searchQuery: "수영장"),
        Rule(keywords: ["경기장", "체육관", "stadium", "sports"], poiKeys: ["stadium"], symbolName: "sportscourt.fill", colorID: "navy"),
        Rule(keywords: ["세탁", "빨래", "코인빨래", "laundry"], poiKeys: ["laundry"], symbolName: "washer.fill", colorID: "teal"),
        Rule(keywords: ["우체국", "택배", "우편", "post"], poiKeys: ["postOffice"], symbolName: "envelope.fill", colorID: "red"),
        Rule(keywords: ["경찰", "지구대", "파출소", "police"], poiKeys: ["police"], symbolName: "shield.lefthalf.filled", colorID: "navy"),
        Rule(keywords: ["소방", "119", "fire"], poiKeys: ["fireStation"], symbolName: "flame.fill", colorID: "red"),
        Rule(keywords: ["호텔", "숙소", "모텔", "게스트하우스", "hotel", "숙박"], poiKeys: ["hotel"], symbolName: "bed.double.fill", colorID: "violet"),
        Rule(keywords: ["학교", "초등", "중학", "고등", "school"], poiKeys: ["school"], symbolName: "graduationcap.fill", colorID: "orange"),
        Rule(keywords: ["대학", "캠퍼스", "university", "college"], poiKeys: ["university"], symbolName: "graduationcap.fill", colorID: "navy"),
        Rule(keywords: ["지하철", "역", "버스", "정류장", "환승", "transit", "subway", "station"], poiKeys: ["publicTransport"], symbolName: "tram.fill", colorID: "blue"),
        Rule(keywords: ["공항", "airport"], poiKeys: ["airport"], symbolName: "airplane", colorID: "blue"),
        Rule(keywords: ["렌터카", "렌트", "rental"], poiKeys: ["carRental"], symbolName: "car.fill", colorID: "gray"),
        Rule(keywords: ["캠핑", "야영", "camping"], poiKeys: ["campground"], symbolName: "tent.fill", colorID: "lime"),
        Rule(keywords: ["해변", "바다", "beach"], poiKeys: ["beach"], symbolName: "sun.max.fill", colorID: "teal"),
        Rule(keywords: ["동물원", "zoo"], poiKeys: ["zoo"], symbolName: "pawprint.fill", colorID: "lime"),
        Rule(keywords: ["아쿠아리움", "수족관", "aquarium"], poiKeys: ["aquarium"], symbolName: "fish.fill", colorID: "teal"),
        Rule(keywords: ["놀이공원", "테마파크", "amusement"], poiKeys: ["amusementPark"], symbolName: "sparkles", colorID: "pink"),
        // POI 분류가 없어 자연어 검색만 쓰는 항목들
        Rule(keywords: ["미용실", "헤어", "이발", "살롱", "barber", "hair"], poiKeys: [], symbolName: "scissors", colorID: "pink"),
        Rule(keywords: ["노래방", "코인노래", "karaoke"], poiKeys: [], symbolName: "music.note", colorID: "violet"),
        Rule(keywords: ["pc방", "피시방", "피씨방"], poiKeys: [], symbolName: "gamecontroller.fill", colorID: "navy"),
        Rule(keywords: ["찜질방", "사우나", "목욕", "spa"], poiKeys: [], symbolName: "flame.fill", colorID: "orange"),
        Rule(keywords: ["꽃집", "화원", "flower", "florist"], poiKeys: [], symbolName: "leaf.fill", colorID: "pink"),
        Rule(keywords: ["동물병원", "펫", "반려", "vet", "pet"], poiKeys: [], symbolName: "pawprint.fill", colorID: "brown"),
        Rule(keywords: ["정비", "카센터", "수리", "repair"], poiKeys: [], symbolName: "hammer.fill", colorID: "gray"),
        Rule(keywords: ["문구", "다이소", "생활용품", "stationery"], poiKeys: [], symbolName: "bag.fill", colorID: "yellow"),
        Rule(keywords: ["무인", "키오스크", "24시"], poiKeys: [], symbolName: "storefront.fill", colorID: "gray"),
        Rule(keywords: ["흡연", "smoking"], poiKeys: [], symbolName: "flame.fill", colorID: "gray"),
        Rule(keywords: ["와이파이", "wifi"], poiKeys: [], symbolName: "wifi", colorID: "blue")
    ]

    static func suggestion(for rawName: String) -> CategorySuggestion {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")

        if let rule = rules.first(where: { rule in
            rule.keywords.contains { normalized.contains($0.lowercased().replacingOccurrences(of: " ", with: "")) }
        }) {
            return CategorySuggestion(
                searchQuery: rule.searchQuery ?? (name.isEmpty ? rule.keywords[0] : name),
                poiRawValues: POICatalog.sanitize(rule.poiKeys),
                symbolName: rule.symbolName,
                colorID: rule.colorID,
                source: .keyword
            )
        }

        return CategorySuggestion(
            searchQuery: name,
            poiRawValues: [],
            symbolName: "mappin.circle.fill",
            colorID: CategoryPalette.options.randomElement()?.id ?? CategoryPalette.fallbackID,
            source: .keyword
        )
    }
}
