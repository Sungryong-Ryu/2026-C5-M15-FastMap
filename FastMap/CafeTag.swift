//
//  CafeTag.swift
//  WhereismyAHAH
//
//  카페를 나누는 고정 태그입니다.
//
//  예전 PlaceCategory는 사용자가 직접 만들고 편집하는 값이었지만, 이제 앱이 카페만 다루므로
//  태그는 앱이 정한 여섯 종류로 고정합니다. 사용자가 고르는 건 "어떤 카페를 볼지"뿐입니다.
//
//  각 태그가 어떻게 판정되는지는 태그마다 다릅니다. `CafeTagClassifier`를 보세요.
//  - 확실한 판정: franchise / independent (브랜드 사전), waterfront (좌표)
//  - 추정 판정:   large / bakery / cozy (상호명·카테고리명 키워드)
//

import SwiftUI

enum CafeTag: String, CaseIterable, Codable, Identifiable, Sendable {
    /// 스타벅스·투썸 같은 브랜드 카페.
    case franchise
    /// 브랜드 사전에 없는 곳. 개인이 하는 카페로 봅니다.
    case independent
    /// 한강·낙동강 같은 큰 물가나 바닷가에 있는 카페.
    case waterfront
    /// 좌석이 많은 대형 카페.
    case large
    /// 빵을 같이 파는 베이커리 카페.
    case bakery
    /// 분위기로 찾아가는 카페. 판정 근거가 가장 약합니다.
    case cozy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .franchise: "프랜차이즈"
        case .independent: "개인카페"
        case .waterfront: "강변·바다뷰"
        case .large: "대형카페"
        case .bakery: "베이커리"
        case .cozy: "분위기"
        }
    }

    var symbolName: String {
        switch self {
        case .franchise: "cup.and.saucer.fill"
        case .independent: "leaf.fill"
        case .waterfront: "water.waves"
        case .large: "building.2.fill"
        case .bakery: "birthday.cake.fill"
        case .cozy: "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .franchise: TossColor.blue
        case .independent: TossCategoryColor.green
        case .waterfront: TossCategoryColor.teal
        case .large: TossCategoryColor.navy
        case .bakery: TossCategoryColor.orange
        case .cozy: TossCategoryColor.violet
        }
    }

    /// 이 태그를 켰을 때 Kakao 키워드 검색으로 추가로 긁어올 검색어.
    ///
    /// 반경 안의 카페(CE7)를 전부 받아 온 다음 걸러내는 게 기본이지만, 그것만으로는
    /// 상호명에 단서가 없는 곳을 놓칩니다. 키워드 검색을 한 번 더 돌려 후보를 넓힙니다.
    /// 비어 있으면 브랜드 사전만으로 판정할 수 있다는 뜻입니다.
    var keywordQueries: [String] {
        switch self {
        case .franchise, .independent:
            []
        case .waterfront:
            ["오션뷰 카페", "바다뷰 카페", "강변 카페", "리버뷰 카페"]
        case .large:
            ["대형카페", "루프탑 카페"]
        case .bakery:
            ["베이커리 카페", "디저트 카페"]
        case .cozy:
            ["감성카페", "분위기 좋은 카페"]
        }
    }

    /// 판정 근거가 약해서 사용자에게 한 번 알려 줄 태그.
    var isHeuristic: Bool {
        switch self {
        case .franchise, .independent, .waterfront: false
        case .large, .bakery, .cozy: true
        }
    }

    /// 칩에 보여 줄 순서. 확실한 것부터 둡니다.
    static let displayOrder: [CafeTag] = [
        .franchise, .independent, .waterfront, .large, .bakery, .cozy
    ]
}
