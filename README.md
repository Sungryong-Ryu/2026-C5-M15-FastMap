# 🌳 FastMap (임시)

> 지금 내 주변에서 '나에게 필요한 장소'를 가장 빠르게 찾는 iOS 지도 앱.

FastMap은 현재 위치를 기준으로 화장실, 카페, 은행, 병원, 음식점, 약국, 편의점, 주차장 같은 주변 장소를 빠르게 탐색하는 SwiftUI 기반 iOS 앱입니다.
지도 위의 마커, 거리순 장소 목록, 도보 경로, 방향 정보, Live Activity를 한 화면 흐름 안에서 제공합니다.

<p align="center">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-iOS-blue?style=flat-square&logo=apple&logoColor=white">
  <img alt="MapKit" src="https://img.shields.io/badge/MapKit-Location-34C759?style=flat-square&logo=apple&logoColor=white">
  <img alt="ActivityKit" src="https://img.shields.io/badge/ActivityKit-Live%20Activity-5856D6?style=flat-square&logo=apple&logoColor=white">
</p>

## 📌 프로젝트 소개

길을 걷다가 "근처 화장실 어디 있지?", "가장 가까운 카페까지 얼마나 남았지?" 같은 순간이 자주 생깁니다. 그럴때 FastMap은 이런 짧고 급한 탐색을 위해 만들어진 앱입니다.

앱을 열면 현재 위치 주변의 주요 장소를 카테고리별로 모아 보여주고, 선택한 장소까지의 거리와 방향을 직관적으로 확인할 수 있습니다. 장소를 선택하면 도보 경로가 지도 위에 표시되고, Live Activity와 Dynamic Island를 통해 앱 밖에서도 목적지 정보를 이어서 볼 수 있습니다.

## ✅ 주요 기능

- 현재 위치 기반 주변 장소 탐색
- 화장실, 카페, 은행, 병원, 음식점, 약국, 편의점, 주차장 카테고리 지원
- 지도 마커와 하단 드로어를 통한 빠른 장소 비교
- 장소명 또는 주소 검색
- 선택한 장소까지의 도보 경로 표시
- 기기 방향에 맞춘 방향 안내 정보 계산
- Live Activity 및 Dynamic Island 위젯 지원
- 위치 권한이 없을 때 서울시청 기준 미리보기 위치 제공

## 🔥 화면 구성

| 주변 탐색 | 카테고리 설정 | Live Activity |
| --- | --- | --- |
| 지도 위에서 가까운 장소를 바로 확인합니다. | 필요한 장소 카테고리만 선택해 탐색 범위를 줄입니다. | 잠금 화면과 Dynamic Island에서 거리와 방향을 이어서 확인합니다. |

> 스크린샷은 추후 `Docs/Images/` 폴더에 추가하면 이 영역에 바로 연결할 수 있습니다.

## 기술 스택

- **SwiftUI**: 메인 화면, 탭, 드로어, 설정 화면 구현
- **MapKit**: 지도, 장소 검색, POI 검색, 도보 경로 계산
- **CoreLocation**: 현재 위치와 기기 방향 추적
- **ActivityKit / WidgetKit**: Live Activity와 Dynamic Island 표시
- **Combine / ObservableObject**: 앱 상태와 장소 목록 관리

## 프로젝트 구조

```text
FastMap/
├── FastMap/
│   ├── ContentView.swift              # 앱의 탭 구조
│   ├── RadarMapView.swift             # 지도, 검색, 장소 드로어
│   ├── CategorySettingsView.swift     # 카테고리 선택 화면
│   ├── FastMapStore.swift             # 장소 목록, 선택 상태, 경로 상태
│   ├── LocationService.swift          # 위치 권한, 현재 위치, 방향 업데이트
│   ├── NearbyPlaceService.swift       # MapKit 기반 주변 장소 검색
│   ├── GeoMath.swift                  # 거리와 방위각 계산
│   └── FastMapModels.swift            # 장소/카테고리 모델
├── FastMapLiveActivity/
│   └── FastMapLiveActivityWidget.swift
├── FastMapShared/
│   └── FastMapActivityAttributes.swift
└── Config/
    └── FastMapLiveActivity-Info.plist
```

## 실행 방법

1. 이 저장소를 클론합니다.
2. `FastMap.xcodeproj`를 Xcode에서 엽니다.
3. `FastMap` scheme을 선택합니다.
4. iPhone Simulator 또는 실제 기기에서 실행합니다.
5. 위치 권한을 허용하면 현재 위치 주변 장소를 탐색할 수 있습니다.

## 개발 메모

- 장소 검색은 `MKLocalSearch`와 `MKLocalPointsOfInterestRequest`를 함께 사용합니다.
- 장소 목록은 현재 위치에서 가까운 순서로 정렬됩니다.
- 사용자가 약 70m 이상 이동하면 주변 장소를 다시 가져옵니다.
- 선택된 장소가 바뀌면 도보 경로와 Live Activity 상태가 함께 갱신됩니다.

## 앞으로 해보고 싶은 것

- 실제 앱 화면 스크린샷 추가
- 카테고리별 커스텀 아이콘 개선
- 즐겨찾기 장소 저장
- 목적지까지 남은 시간 표시
- 접근성 옵션 강화
- 지도 스타일과 테마 선택 기능

## Team

2026-C5-M15 FastMap

🍀
