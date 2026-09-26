import Foundation
import CoreLocation
import SwiftUI

/// The type of water point. The app shows each type with its own symbol.
enum SpotKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case fountain
    case tap
    case business
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fountain: "Fountain"
        case .tap: "Tap"
        case .business: "Business"
        case .other: "Other"
        }
    }

    var longLabel: String {
        switch self {
        case .fountain: "Drinking fountain"
        case .tap: "Tap or spigot"
        case .business: "Business that gives water"
        case .other: "Other water source"
        }
    }

    var symbol: String {
        switch self {
        case .fountain: "drop.fill"
        case .tap: "spigot.fill"
        case .business: "cup.and.saucer.fill"
        case .other: "mappin"
        }
    }

    /// Public water is blue. Businesses (ask first) are amber. Other is slate.
    var tint: Color {
        switch self {
        case .business: Color(red: 0.85, green: 0.55, blue: 0.10)
        case .other: Color(red: 0.35, green: 0.45, blue: 0.55)
        default: Color(red: 0.10, green: 0.45, blue: 0.85)
        }
    }
}

/// One water point. Phase 1 gets all points from OpenStreetMap.
/// Phase 2 adds community points from the backend with the same model.
struct WaterSpot: Identifiable, Codable, Hashable {
    enum Source: String, Codable { case openStreetMap, community }

    let id: String            // "node/123" for OSM
    let source: Source
    let latitude: Double
    let longitude: Double
    let kind: SpotKind
    let tags: [String: String]

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }

    var displayName: String { tags["name"] ?? kind.longLabel }
    var hasBottleFiller: Bool { tags["bottle"] == "yes" }
    var seasonal: String? { tags["seasonal"].flatMap { $0 == "no" ? nil : $0 } }
    var fee: String? { tags["fee"] }
    var openingHours: String? { tags["opening_hours"] }
    var access: String? { tags["access"] }
    var lastChecked: String? { tags["check_date"] ?? tags["survey:date"] }
    var note: String? { tags["description"] ?? tags["note"] }

    var osmURL: URL? {
        guard source == .openStreetMap else { return nil }
        return URL(string: "https://www.openstreetmap.org/\(id)")
    }
}

extension WaterSpot {
    /// Makes a spot from OSM tags. Returns nil if the point is not public drinking water.
    init?(osmType: String, osmID: Int64, latitude: Double, longitude: Double, tags: [String: String]) {
        if tags["drinking_water"] == "no" { return nil }
        if let access = tags["access"], ["private", "no", "customers"].contains(access) { return nil }

        self.id = "\(osmType)/\(osmID)"
        self.source = .openStreetMap
        self.latitude = latitude
        self.longitude = longitude
        self.tags = tags
        self.kind = Self.classify(tags)
    }

    static func classify(_ tags: [String: String]) -> SpotKind {
        let amenity = tags["amenity"] ?? ""
        if amenity == "drinking_water" { return .fountain }
        if tags["man_made"] == "water_tap" || amenity == "water_point" { return .tap }
        if tags["drinking_water:refill"] == "yes" { return .business }
        let businessAmenities: Set = ["cafe", "restaurant", "fast_food", "pub", "bar", "fuel", "ice_cream", "bicycle_rental"]
        if tags["shop"] != nil || businessAmenities.contains(amenity) { return .business }
        return .other
    }
}
