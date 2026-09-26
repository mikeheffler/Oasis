import Foundation

/// The OSM tag rules for water points. The explorer (tools/explorer/index.html)
/// has the same rules in JavaScript. Change both together.
public enum OSMRules {
    /// Why a tagged feature is not shown as public drinking water.
    public enum Exclusion: Equatable, Sendable {
        /// `drinking_water=no`.
        case notDrinkable
        /// `access` is private, no, or customers.
        case restrictedAccess(String)
    }

    public static let restrictedAccessValues: Set<String> = ["private", "no", "customers"]

    /// Amenity values that count as a business when there is no stronger signal.
    public static let businessAmenities: Set<String> = [
        "cafe", "restaurant", "fast_food", "pub", "bar", "fuel", "ice_cream", "bicycle_rental",
    ]

    /// Returns nil when the feature is public drinking water.
    public static func exclusion(for tags: [String: String]) -> Exclusion? {
        if tags["drinking_water"] == "no" { return .notDrinkable }
        if let access = tags["access"], restrictedAccessValues.contains(access) {
            return .restrictedAccess(access)
        }
        return nil
    }

    /// Picks the kind. The first matching rule wins.
    public static func classify(_ tags: [String: String]) -> SpotKind {
        let amenity = tags["amenity"] ?? ""
        if amenity == "drinking_water" { return .fountain }
        if tags["man_made"] == "water_tap" || amenity == "water_point" { return .tap }
        if tags["drinking_water:refill"] == "yes" { return .business }
        if tags["shop"] != nil || businessAmenities.contains(amenity) { return .business }
        return .other
    }
}
