import Foundation

/// The OSM tag rules for water points. The explorer (tools/explorer/index.html)
/// has the same rules in JavaScript. Change both together.
public enum OSMRules {
    /// Why a tagged feature is hidden.
    public enum Exclusion: Equatable, Sendable {
        /// `drinking_water=no` on a place that does not sell water.
        case notDrinkable
        /// `access` is private or no, or customers on a place that does not sell water.
        case restrictedAccess(String)
        /// A tag says the feature is broken, closed, or not used, e.g. "operational_status=broken".
        case problem(String)
    }

    public enum Decision: Equatable, Sendable {
        case show(SpotKind)
        case hide(Exclusion)
    }

    /// `operational_status` values that mean the water does not work.
    public static let problemStatuses: Set<String> = [
        "broken", "closed", "out_of_order", "out_of_service", "non-operational", "non_operational",
    ]

    /// Amenity values that count as a business with free water when tagged `drinking_water=yes`.
    public static let freeWaterBusinessAmenities: Set<String> = [
        "cafe", "restaurant", "fast_food", "pub", "bar", "fuel", "ice_cream", "bicycle_rental",
    ]

    /// Places that sell water or other drinks.
    public static let buyShops: Set<String> = ["convenience", "supermarket", "general", "kiosk"]
    public static let buyAmenities: Set<String> = ["fuel", "cafe", "fast_food", "restaurant"]
    /// `vending=*` values (the tag is a semicolon list) for drink machines.
    public static let drinkVending: Set<String> = ["drinks", "water", "bottled_water", "cold_drinks"]

    /// Decides if a feature shows, and as which kind.
    public static func evaluate(_ tags: [String: String]) -> Decision {
        if let problem = problem(in: tags) { return .hide(.problem(problem)) }
        if let access = tags["access"], access == "private" || access == "no" {
            return .hide(.restrictedAccess(access))
        }
        // You can still buy water where the tap water is not for the public.
        let sells = sellsDrinks(tags)
        if tags["drinking_water"] == "no" { return sells ? .show(.buy) : .hide(.notDrinkable) }
        if tags["access"] == "customers" { return sells ? .show(.buy) : .hide(.restrictedAccess("customers")) }
        return .show(classify(tags))
    }

    /// Picks the kind for a feature that is not hidden. The first matching rule wins.
    public static func classify(_ tags: [String: String]) -> SpotKind {
        let amenity = tags["amenity"] ?? ""
        if amenity == "drinking_water" { return .fountain }
        if tags["man_made"] == "water_tap" || amenity == "water_point" { return .tap }
        if tags["drinking_water:refill"] == "yes" { return .business }
        let sells = sellsDrinks(tags)
        if tags["drinking_water"] == "yes",
           tags["shop"] != nil || freeWaterBusinessAmenities.contains(amenity) || sells {
            return .business
        }
        if sells { return .buy }
        return .other
    }

    /// True for stores, gas stations, cafes, restaurants, and drink vending machines.
    public static func sellsDrinks(_ tags: [String: String]) -> Bool {
        if let shop = tags["shop"], buyShops.contains(shop) { return true }
        let amenity = tags["amenity"] ?? ""
        if buyAmenities.contains(amenity) { return true }
        if amenity == "vending_machine", let vending = tags["vending"] {
            return vending.split(separator: ";").contains { drinkVending.contains($0.trimmingCharacters(in: .whitespaces)) }
        }
        return false
    }

    /// The first tag that marks the feature as broken, closed, or not used.
    public static func problem(in tags: [String: String]) -> String? {
        if let status = tags["operational_status"], problemStatuses.contains(status) {
            return "operational_status=\(status)"
        }
        for key in ["disused", "abandoned"] where tags[key] == "yes" { return "\(key)=yes" }
        return nil
    }
}
