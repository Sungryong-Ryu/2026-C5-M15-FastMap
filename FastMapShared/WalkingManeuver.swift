//
//  WalkingManeuver.swift
//  FastMapShared
//
//  도보 안내의 다음 동작.
//  MKRoute.Step은 조작 종류를 공개하지 않기 때문에 안내 문구에서 추정합니다.
//  앱과 Live Activity 위젯이 같은 아이콘을 쓰도록 공유 타깃에 둡니다.
//

import Foundation

enum WalkingManeuver: String, Codable, Hashable, Sendable, CaseIterable {
    case straight
    case slightLeft
    case left
    case slightRight
    case right
    case uTurn
    case crosswalk
    case arrive

    var symbolName: String {
        switch self {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.up"
        case .crosswalk: "figure.walk"
        case .arrive: "flag.checkered"
        }
    }

    /// 접근성 라벨용 짧은 설명.
    var title: String {
        switch self {
        case .straight: "직진"
        case .slightLeft: "왼쪽 방향"
        case .left: "좌회전"
        case .slightRight: "오른쪽 방향"
        case .right: "우회전"
        case .uTurn: "유턴"
        case .crosswalk: "횡단보도 건너기"
        case .arrive: "도착"
        }
    }

    /// 안내 문구에서 동작을 추정합니다. 한국어와 영어를 모두 봅니다.
    /// 순서가 중요합니다. "좌회전"을 먼저 걸러야 일반적인 "왼쪽"으로 빠지지 않습니다.
    static func infer(from instruction: String) -> WalkingManeuver {
        let text = instruction.lowercased()

        func contains(_ keywords: [String]) -> Bool {
            keywords.contains { text.contains($0) }
        }

        if contains(["도착", "목적지", "arrive", "destination"]) { return .arrive }
        if contains(["유턴", "u-turn", "uturn"]) { return .uTurn }
        if contains(["좌회전", "turn left"]) { return .left }
        if contains(["우회전", "turn right"]) { return .right }
        if contains(["횡단보도", "건너", "crosswalk", "cross the"]) { return .crosswalk }
        if contains(["왼쪽", "slight left", "keep left", "bear left", "left"]) { return .slightLeft }
        if contains(["오른쪽", "slight right", "keep right", "bear right", "right"]) { return .slightRight }

        return .straight
    }
}
