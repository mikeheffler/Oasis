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

    /// Places that sell water or other drinks, by category.
    public static let convenienceShops: Set<String> = ["convenience", "general", "kiosk"]
    public static let convenienceAmenities: Set<String> = ["fuel"]
    public static let groceryShops: Set<String> = ["supermarket"]
    public static let restaurantAmenities: Set<String> = ["restaurant", "cafe", "fast_food"]
    /// `vending=*` values (the tag is a semicolon list) for drink machines. They count as convenience.
    public static let drinkVending: Set<String> = ["drinks", "water", "bottled_water", "cold_drinks"]

    /// All shop and amenity values for the buy-water query.
    public static var buyShops: Set<String> { convenienceShops.union(groceryShops) }
    public static var buyAmenities: Set<String> { convenienceAmenities.union(restaurantAmenities) }

    /// Decides if a feature shows, and as which kind.
    public static func evaluate(_ tags: [String: String]) -> Decision {
        if let problem = problem(in: tags) { return .hide(.problem(problem)) }
        if let access = tags["access"], access == "private" || access == "no" {
            return .hide(.restrictedAccess(access))
        }
        // You can still buy water where the tap water is not for the public.
        if tags["drinking_water"] == "no" {
            return buyKind(tags).map(Decision.show) ?? .hide(.notDrinkable)
        }
        if tags["access"] == "customers" {
            return buyKind(tags).map(Decision.show) ?? .hide(.restrictedAccess("customers"))
        }
        return .show(classify(tags))
    }

    /// Picks the kind for a feature that is not hidden. The first matching rule wins.
    public static func classify(_ tags: [String: String]) -> SpotKind {
        let amenity = tags["amenity"] ?? ""
        if amenity == "drinking_water" { return .fountain }
        if tags["man_made"] == "water_tap" || amenity == "water_point" { return .tap }
        if tags["drinking_water:refill"] == "yes" { return .business }
        let buy = buyKind(tags)
        if tags["drinking_water"] == "yes",
           tags["shop"] != nil || freeWaterBusinessAmenities.contains(amenity) || buy != nil {
            return .business
        }
        return buy ?? .other
    }

    /// The buy category of a place that sells drinks, or nil.
    /// Grocery wins over convenience, and convenience over restaurant, for mixed tags.
    public static func buyKind(_ tags: [String: String]) -> SpotKind? {
        let shop = tags["shop"] ?? "", amenity = tags["amenity"] ?? ""
        if groceryShops.contains(shop) { return .grocery }
        if convenienceShops.contains(shop) || convenienceAmenities.contains(amenity) { return .convenience }
        if amenity == "vending_machine", let vending = tags["vending"],
           vending.split(separator: ";").contains(where: { drinkVending.contains($0.trimmingCharacters(in: .whitespaces)) }) {
            return .convenience
        }
        if restaurantAmenities.contains(amenity) { return .restaurant }
        return nil
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
