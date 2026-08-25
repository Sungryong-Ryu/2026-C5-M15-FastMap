# 아아딨지

현재 위치나 사용자가 지도에서 보고 있는 지역의 카페를 빠르게 찾는 SwiftUI 지도 앱입니다. 앱을 열면 지도가 바로 보이고, 하단 검색창과 카페 유형 필터로 원하는 카페를 좁힐 수 있어요.

## 주요 기능

- 현재 위치 또는 이동한 지도 화면의 카페를 지도 마커로 표시.
- 하단 드로어에서 카페명·지역 검색.
- 프랜차이즈, 개인카페, 강변·바다뷰, 대형카페, 베이커리, 분위기 필터.
- 전체·50m·100m·200m·500m·1km 거리 필터.
- 가까운 순 카페 목록과 도보·자동차·자전거·대중교통 길찾기.
- 카카오맵 상세 페이지 연결, 즐겨찾기, 이동수단별 Live Activity 길안내.
- 길안내 화면의 Apple Music 미니 플레이어와 외부 음악 재생 유지.
- 검색 중심이 국내면 Kakao Local API, 해외면 Apple MapKit으로 자동 전환.
- 국내에서 Kakao Local API를 사용할 수 없을 때 Apple MapKit 검색으로 자동 대체.

## 카페 데이터

검색 중심 좌표가 대한민국이면 Kakao Local REST API를 사용하고, 해외이면 Apple MapKit으로 자동 전환합니다. 현재 위치뿐 아니라 사용자가 지도를 옮긴 지역과 직접 검색의 기준 좌표에도 같은 규칙을 적용해요. 국내에서는 공식 카테고리 검색 API의 카페 코드(`CE7`)로 주변 장소를 조회하며, REST API 키가 없거나 요청이 실패하면 MapKit으로 전환합니다. 길찾기는 같은 REST 키로 Kakao Map의 도보·자전거·대중교통 경로와 Kakao Mobility의 자동차 경로를 조회해요.

1. Kakao Developers에서 앱을 만들고 REST API 키를 발급합니다.
2. `FastMap/Secrets.example.plist`를 `FastMap/Secrets.plist`로 복사합니다.
3. `KAKAO_REST_API_KEY` 값에 키를 입력합니다.

`Secrets.plist`는 Git에서 제외됩니다. 카카오 응답은 화면 표시 중 메모리에서만 사용하며, 저장이 필요한 즐겨찾기는 Apple MapKit 결과로 다시 확인한 뒤 보관합니다.

## 실행

1. `FastMap.xcodeproj`를 Xcode에서 엽니다.
2. `FastMap` scheme과 실행할 iPhone을 선택합니다.
3. 앱을 실행하고 위치 권한을 허용합니다.

홈 화면과 시스템 표시 이름은 `아아딨지`입니다. 기존 프로젝트/타깃 식별자는 서명과 Live Activity 호환성을 위해 유지했습니다.
