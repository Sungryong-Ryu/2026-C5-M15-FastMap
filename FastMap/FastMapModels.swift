import CoreLocation
import Foundation
import MapKit
import SwiftUI

enum AppTab: Hashable {
    case radar
    case categories
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
