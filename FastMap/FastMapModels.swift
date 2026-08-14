import CoreLocation
import Foundation
import MapKit
import SwiftUI

enum AppTab: Hashable {
    case radar
    case categories
}

enum PlaceCategory: String, CaseIterable, Identifiable, Codable {
    case searchResult
    case restroom
    case cafe
    case bank
    case hospital
    case restaurant
    case pharmacy
    case convenienceStore
    case parking

    var id: String { rawValue }

    static var quickCategories: [PlaceCategory] {
        allCases.filter { $0 != .searchResult }
    }

    var title: String {
        switch self {
        case .searchResult: "검색 결과"
        case .restroom: "화장실"
        case .cafe: "카페"
        case .bank: "은행"
        case .hospital: "병원"
        case .restaurant: "음식점"
        case .pharmacy: "약국"
        case .convenienceStore: "편의점"
        case .parking: "주차장"
        }
    }

    var koreanQuery: String {
        switch self {
        case .searchResult: "검색"
        case .restroom: "화장실"
        case .cafe: "카페"
        case .bank: "은행"
        case .hospital: "병원"
        case .restaurant: "음식점"
        case .pharmacy: "약국"
        case .convenienceStore: "편의점"
        case .parking: "주차장"
        }
    }

    var symbolName: String {
        switch self {
        case .searchResult: "mappin.circle.fill"
        case .restroom: "figure.stand"
        case .cafe: "cup.and.saucer.fill"
        case .bank: "building.columns.fill"
        case .hospital: "cross.fill"
        case .restaurant: "fork.knife"
        case .pharmacy: "cross.case.fill"
        case .convenienceStore: "basket.fill"
        case .parking: "parkingsign.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .searchResult: .purple
        case .restroom: .teal
        case .cafe: .mint
        case .bank: .indigo
        case .hospital: .pink
        case .restaurant: .green
        case .pharmacy: .red
        case .convenienceStore: .orange
        case .parking: .blue
        }
    }
}

struct Place: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let category: PlaceCategory
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let bearingDegrees: Double

    var mapItem: MKMapItem {
        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        item.name = name
        return item
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case address
        case latitude
        case longitude
        case distanceMeters
        case bearingDegrees
    }

    init(
        id: String,
        name: String,
        category: PlaceCategory,
        address: String,
        coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.address = address
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.bearingDegrees = bearingDegrees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(PlaceCategory.self, forKey: .category)
        address = try container.decode(String.self, forKey: .address)
        let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
        let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        bearingDegrees = try container.decode(Double.self, forKey: .bearingDegrees)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(address, forKey: .address)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(distanceMeters, forKey: .distanceMeters)
        try container.encode(bearingDegrees, forKey: .bearingDegrees)
    }
}

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
    static let seoulCityHall = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
}
