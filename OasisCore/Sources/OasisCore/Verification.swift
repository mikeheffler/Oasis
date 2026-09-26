import Foundation

/// Is there recent evidence that the water point works?
/// Phase 1 uses OSM survey dates only. Phase 2 adds Oasis user reports.
public enum Verification: String, Codable, Sendable {
    case verified
    case unverified
}

public enum VerificationRules {
    /// A survey date inside this window makes a point verified.
    public static let windowMonths = 24

    /// Verified if `check_date` or `survey:date` is within `windowMonths` before `now`.
    /// An ordinary edit does not count: it does not show that someone saw the water work.
    public static func verification(for tags: [String: String], asOf now: Date,
                                    windowMonths: Int = windowMonths) -> Verification {
        guard let date = surveyDate(in: tags, asOf: now),
              // OSM dates have no time, so compare whole UTC days.
              let cutoff = utc.date(byAdding: .month, value: -windowMonths, to: utc.startOfDay(for: now)),
              date >= cutoff else { return .unverified }
        return .verified
    }

    /// The latest valid survey date. Ignores dates more than one day in the future (typos).
    public static func surveyDate(in tags: [String: String], asOf now: Date) -> Date? {
        let limit = now.addingTimeInterval(24 * 60 * 60)
        return [tags["check_date"], tags["survey:date"]]
            .compactMap { $0 }
            .flatMap { $0.split(separator: ";") }
            .compactMap { parseDate(String($0)) }
            .filter { $0 <= limit }
            .max()
    }

    /// Parses OSM date values: "YYYY-MM-DD", "YYYY-MM", or "YYYY" (UTC, first day of the period).
    /// A time after the date ("2024-05-01T10:00Z") is ignored.
    public static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let parts = text.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts[0].count == 4, let year = Int(parts[0]) else { return nil }
        var c = DateComponents(year: year, month: 1, day: 1)
        if parts.count >= 2 {
            guard parts[1].count == 2, let m = Int(parts[1]), (1...12).contains(m) else { return nil }
            c.month = m
        }
        if parts.count == 3 {
            guard parts[2].count == 2, let d = Int(parts[2]), (1...31).contains(d) else { return nil }
            c.day = d
        }
        guard let date = utc.date(from: c),
              utc.component(.day, from: date) == c.day else { return nil } // rejects 2024-02-31
        return date
    }

    static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
}

extension WaterSpot {
    public func verification(asOf now: Date = Date()) -> Verification {
        VerificationRules.verification(for: tags, asOf: now)
    }
}
