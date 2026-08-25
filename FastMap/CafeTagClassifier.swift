//
//  CafeTagClassifier.swift
//  WhereismyAHAH
//
//  카페 하나에 태그를 붙입니다. 전부 온디바이스에서, 네트워크 없이 계산합니다.
//
//  판정 근거가 태그마다 다르고, 그 차이를 숨기지 않는 게 이 파일의 요점입니다.
//
//  확실한 것
//  - franchise / independent: 브랜드 사전에 상호명이나 카카오 분류 마지막 토큰이 걸리는지.
//  - waterfront: 좌표가 강 중심선이나 해안 지역 안에 드는지. (`WaterProximity`)
//
//  추정하는 것 — 상호명과 카카오 분류에 남은 단서로 짐작합니다
//  - bakery: "제과,베이커리" 분류나 빵 관련 단어. 셋 중에는 제일 잘 맞습니다.
//  - large:  로스터리·팩토리처럼 큰 매장에 자주 붙는 단어. 놓치는 게 많습니다.
//  - cozy:   감성·루프탑·테라스 같은 단어. 근거가 가장 약합니다.
//
//  Kakao Local API 응답에는 평점도 리뷰 수도 없어서 "분위기"를 뒷받침할 데이터가 없습니다.
//  나중에 평점을 주는 소스를 붙이면 `cozyTags(...)` 안쪽만 갈아 끼우면 됩니다.
//

import CoreLocation
import Foundation

enum CafeTagClassifier {

    /// 카페 하나에 붙일 태그 전체.
    static func tags(
        name: String,
        categoryName: String?,
        coordinate: CLLocationCoordinate2D
    ) -> Set<CafeTag> {
        let haystack = normalized(name + " " + (categoryName ?? ""))
        var result: Set<CafeTag> = []

        if matchedFranchise(name: name, categoryName: categoryName) != nil {
            result.insert(.franchise)
        } else {
            result.insert(.independent)
        }

        if WaterProximity.isWaterfront(coordinate) {
            result.insert(.waterfront)
        }

        if contains(haystack, any: bakeryKeywords) {
            result.insert(.bakery)
        }
        if contains(haystack, any: largeKeywords) {
            result.insert(.large)
        }
        if contains(haystack, any: cozyKeywords) {
            result.insert(.cozy)
        }

        return result
    }

    /// 걸린 브랜드 이름. 상세 화면에 "스타벅스" 같이 보여 줄 때 씁니다.
    static func matchedFranchise(name: String, categoryName: String?) -> String? {
        let normalizedName = normalized(name)
        // 카카오 분류는 "음식점 > 카페 > 커피전문점 > 스타벅스" 꼴이라 마지막 토큰이 브랜드입니다.
        let categoryLeaf = categoryName?
            .split(separator: ">")
            .last
            .map { normalized(String($0)) }

        for brand in franchiseBrands {
            for alias in brand.aliases {
                let key = normalized(alias)
                guard !key.isEmpty else { continue }
                if normalizedName.contains(key) { return brand.displayName }
                if let categoryLeaf, categoryLeaf.contains(key) { return brand.displayName }
            }
        }
        return nil
    }

    // MARK: - 브랜드 사전

    struct Franchise {
        let displayName: String
        /// 상호명에 실제로 찍히는 표기들. 띄어쓰기·대소문자는 비교 전에 지웁니다.
        let aliases: [String]
    }

    /// 새 브랜드가 생기면 여기에 한 줄 추가하면 됩니다.
    static let franchiseBrands: [Franchise] = [
        .init(displayName: "스타벅스", aliases: ["스타벅스", "starbucks"]),
        .init(displayName: "투썸플레이스", aliases: ["투썸플레이스", "투썸", "twosome"]),
        .init(displayName: "이디야커피", aliases: ["이디야", "ediya"]),
        .init(displayName: "메가커피", aliases: ["메가커피", "메가엠지씨커피", "megacoffee", "megamgc"]),
        .init(displayName: "컴포즈커피", aliases: ["컴포즈커피", "컴포즈", "composecoffee"]),
        .init(displayName: "빽다방", aliases: ["빽다방", "paikdabang"]),
        .init(displayName: "더벤티", aliases: ["더벤티", "theventi"]),
        .init(displayName: "매머드커피", aliases: ["매머드커피", "매머드익스프레스", "mammoth"]),
        .init(displayName: "할리스", aliases: ["할리스", "hollys"]),
        .init(displayName: "커피빈", aliases: ["커피빈", "coffeebean"]),
        .init(displayName: "파스쿠찌", aliases: ["파스쿠찌", "pascucci"]),
        .init(displayName: "탐앤탐스", aliases: ["탐앤탐스", "tomntoms"]),
        .init(displayName: "엔제리너스", aliases: ["엔제리너스", "angelinus"]),
        .init(displayName: "폴 바셋", aliases: ["폴바셋", "paulbassett"]),
        .init(displayName: "카페베네", aliases: ["카페베네", "caffebene"]),
        .init(displayName: "요거프레소", aliases: ["요거프레소", "yogerpresso"]),
        .init(displayName: "커피에 반하다", aliases: ["커피에반하다"]),
        .init(displayName: "셀렉토커피", aliases: ["셀렉토", "selecto"]),
        .init(displayName: "드롭탑", aliases: ["드롭탑", "droptop"]),
        .init(displayName: "만랩커피", aliases: ["만랩커피", "manlab"]),
        .init(displayName: "더리터", aliases: ["더리터", "theliter"]),
        .init(displayName: "커피나무", aliases: ["커피나무"]),
        .init(displayName: "토프레소", aliases: ["토프레소", "topresso"]),
        .init(displayName: "커피스미스", aliases: ["커피스미스", "coffeesmith"]),
        .init(displayName: "감성커피", aliases: ["감성커피"]),
        .init(displayName: "백억커피", aliases: ["백억커피"]),
        .init(displayName: "블루보틀", aliases: ["블루보틀", "bluebottle"]),
        .init(displayName: "테라로사", aliases: ["테라로사", "terarosa"]),
        .init(displayName: "프릳츠", aliases: ["프릳츠", "fritz"]),
        .init(displayName: "공차", aliases: ["공차", "gongcha"]),
        .init(displayName: "쥬씨", aliases: ["쥬씨", "juicy"]),
        .init(displayName: "스무디킹", aliases: ["스무디킹", "smoothieking"]),
        .init(displayName: "설빙", aliases: ["설빙", "sulbing"]),
        .init(displayName: "배스킨라빈스", aliases: ["배스킨라빈스", "baskinrobbins"]),
        .init(displayName: "던킨", aliases: ["던킨", "dunkin"]),
        .init(displayName: "크리스피크림", aliases: ["크리스피크림", "krispykreme"]),
        .init(displayName: "파리바게뜨", aliases: ["파리바게뜨", "parisbaguette"]),
        .init(displayName: "뚜레쥬르", aliases: ["뚜레쥬르", "tourlesjours"]),
        .init(displayName: "브레댄코", aliases: ["브레댄코", "breadnco"])
    ]

    // MARK: - 키워드 규칙

    /// 빵을 같이 파는 곳. 카카오 분류에 "제과,베이커리"가 붙는 경우가 많아 적중률이 높습니다.
    private static let bakeryKeywords = [
        "베이커리", "bakery", "제과", "브레드", "bread", "빵",
        "파티세리", "patisserie", "파티스리", "케이크", "cake",
        "디저트", "dessert", "도넛", "donut", "doughnut",
        "크로플", "크루아상", "스콘", "타르트", "마카롱", "브런치", "brunch"
    ]

    /// 큰 매장에 자주 붙는 단어. 작은 로스터리도 걸리므로 오탐이 있습니다.
    private static let largeKeywords = [
        "로스터리", "로스터스", "roastery", "roasters", "roasting",
        "팩토리", "factory", "웨어하우스", "warehouse", "창고",
        "가든", "garden", "빌리지", "village", "파크", "park",
        "커피공장", "베이커리카페", "대형", "본점"
    ]

    /// 분위기로 찾아가는 곳. 셋 중 근거가 가장 약합니다.
    private static let cozyKeywords = [
        "감성", "아뜰리에", "atelier", "온실", "정원",
        "뷰", "view", "오션", "ocean", "씨사이드", "seaside",
        "테라스", "terrace", "루프탑", "rooftop",
        "라운지", "lounge", "살롱", "salon", "하우스", "house",
        "브루잉", "brewing", "스페셜티", "specialty", "핸드드립",
        "빈티지", "vintage", "고택", "한옥", "책방", "북카페"
    ]

    // MARK: - 문자열 보조

    /// 띄어쓰기·마침표·하이픈을 지우고 소문자로 맞춥니다.
    /// "폴 바셋"과 "폴바셋", "TWOSOME"과 "twosome"을 같게 보기 위한 처리입니다.
    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && $0 != "." && $0 != "-" && $0 != "_" }
    }

    private static func contains(_ haystack: String, any needles: [String]) -> Bool {
        needles.contains { haystack.contains(normalized($0)) }
    }
}
