import Foundation

/// The Oasis Supabase project. Both values are public by design:
/// row-level security in supabase/migrations protects the data.
enum SupabaseConfig {
    static let url = URL(string: "https://scbkoxbdzaipkxwyvrql.supabase.co")!
    static let publishableKey = "sb_publishable_GIP_IsErO92gY3H5eCBBfg_OS-viury"
}

enum DataSources {
    /// The backend by default. In debug builds, set the scheme environment variable
    /// OASIS_SOURCE=overpass to read the public Overpass server instead (development only).
    static func makeDefault() -> any WaterSpotSource {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OASIS_SOURCE"] == "overpass" {
            return OverpassClient()
        }
        #endif
        return SupabaseSource()
    }
}
