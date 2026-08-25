//
//  AppSecrets.swift
//  CoFFMap
//
//  Kakao REST API 키를 읽습니다.
//
//  키는 `Secrets.plist`에 두고 git에는 올리지 않습니다. 같이 들어 있는
//  `Secrets.example.plist`를 복사해서 이름을 바꾸고 키를 채우면 됩니다.
//
//  키가 없어도 앱은 돌아갑니다. `CafeStore`가 Apple 지도 검색으로 대신 채우고,
//  화면에는 "Kakao 키가 없어 Apple 지도로 찾는 중"이라고 알려 줍니다.
//  발표나 데모에서 키 없이 켜도 빈 화면이 나오지 않게 하려는 장치입니다.
//

import Foundation

enum AppSecrets {
    /// Kakao Developers > 내 애플리케이션 > 앱 키 > REST API 키.
    static let kakaoRESTAPIKey: String? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }

        // README와 예시 파일은 KAKAO_REST_API_KEY를 씁니다.
        // 예전에 KakaoRESTAPIKey로 넣어 둔 경우도 그대로 읽어 줍니다.
        let candidates = ["KAKAO_REST_API_KEY", "KakaoRESTAPIKey"]
        guard let key = candidates.lazy.compactMap({ dictionary[$0] as? String }).first
        else { return nil }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // 예시 파일을 그대로 복사만 하고 키를 안 채운 경우를 걸러 냅니다.
        guard !trimmed.isEmpty, trimmed != "여기에_REST_API_키를_넣으세요" else { return nil }
        return trimmed
    }()

    static var hasKakaoKey: Bool { kakaoRESTAPIKey != nil }
}
