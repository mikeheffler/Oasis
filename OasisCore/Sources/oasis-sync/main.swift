// oasis-sync: copies OSM water points for a region into the Supabase `osm_points` table.
//
//   swift run -c release oasis-sync [--region colorado] [--dry-run] [--max-tiles N]
//   swift run oasis-sync --fixture path/to/overpass.json      (parse one file, no network)
//
// Environment (not needed with --dry-run or --fixture):
//   SUPABASE_URL          https://<ref>.supabase.co
//   SUPABASE_SECRET_KEY   sb_secret_… (GitHub Actions secret only)
//   OVERPASS_URL          optional, default https://overpass-api.de/api/interpreter
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OasisCore

struct Options {
    var region = SyncRegion.colorado
    var dryRun = false
    var maxTiles = Int.max
    var fixture: String?
}

/// Unbuffered output, so a CI log shows progress while the run is going
/// (`print` is fully buffered when stdout is not a terminal).
func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

func parseOptions() -> Options {
    var o = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        switch arg {
        case "--region":
            guard let name = args.next(), let r = SyncRegion.named(name) else { fail("unknown region") }
            o.region = r
        case "--dry-run": o.dryRun = true
        case "--max-tiles":
            guard let n = args.next().flatMap(Int.init), n > 0 else { fail("--max-tiles needs a number") }
            o.maxTiles = n
        case "--fixture":
            guard let path = args.next() else { fail("--fixture needs a path") }
            o.fixture = path
        default: fail("unknown argument \(arg)")
        }
    }
    return o
}

enum SyncError: Error, CustomStringConvertible {
    case http(Int, String)
    var description: String {
        switch self {
        case .http(let code, let body): "HTTP \(code): \(body.prefix(300))"
        }
    }
}

let userAgent = "Oasis-sync/0.1 (+https://github.com/mikeheffler/Oasis)"

/// POST that returns the body, or throws with the status and body.
func post(_ url: URL, body: Data, headers: [String: String], timeout: TimeInterval) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.timeoutInterval = timeout
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        throw SyncError.http(status, String(decoding: data, as: UTF8.self))
    }
    return data
}

/// Overpass with polite retries: wait 60 s, then 120 s. A 4xx other than 429 is not retried.
func fetchTile(_ tile: BoundingBox, overpass: URL) async throws -> OverpassResponse {
    let body = OverpassQuery.formBody(for: OSMSync.query(for: tile))
    var lastError: Error?
    for attempt in 0..<3 {
        if attempt > 0 { try await Task.sleep(nanoseconds: UInt64(60 * attempt) * 1_000_000_000) }
        do {
            let data = try await post(overpass, body: body,
                                      headers: ["Content-Type": "application/x-www-form-urlencoded"],
                                      timeout: 200)
            return try OverpassResponse.decode(data)
        } catch SyncError.http(let code, let text) where code != 429 && code < 500 {
            throw SyncError.http(code, text) // a bad request: a retry cannot help
        } catch {
            // 429, 5xx, network errors (not always URLError on Linux), a busy page that is not JSON.
            lastError = error
            say("  attempt \(attempt + 1) failed: \(error)")
        }
    }
    throw lastError!
}

struct Supabase {
    let base: URL
    let key: String

    var headers: [String: String] {
        // New-style keys go in the apikey header only; the gateway maps them to a role.
        ["apikey": key, "Content-Type": "application/json"]
    }

    func upsert(_ rows: [OSMPointRow]) async throws {
        let url = base.appendingPathComponent("rest/v1/osm_points")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "osm_id")]
        var h = headers
        h["Prefer"] = "resolution=merge-duplicates,return=minimal"
        for start in stride(from: 0, to: rows.count, by: 500) {
            let chunk = Array(rows[start..<min(start + 500, rows.count)])
            _ = try await post(components.url!, body: try JSONEncoder().encode(chunk), headers: h, timeout: 120)
        }
    }

    /// Marks points in the tile that this run did not see as removed. Returns the count.
    func markRemoved(in tile: BoundingBox, runStarted: String) async throws -> Int {
        let url = base.appendingPathComponent("rest/v1/rpc/mark_removed_osm_points")
        let args: [String: String] = [
            "west": "\(tile.west)", "south": "\(tile.south)", "east": "\(tile.east)",
            "north": "\(tile.north)", "run_started": runStarted,
        ]
        let data = try await post(url, body: try JSONEncoder().encode(args), headers: headers, timeout: 120)
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
}

// MARK: - Main

let options = parseOptions()
let runStarted = Date()
let runStartedText = ISO8601DateFormatter().string(from: runStarted)

if let path = options.fixture {
    guard let data = FileManager.default.contents(atPath: path) else { fail("cannot read \(path)") }
    do {
        let rows = try OSMSync.rows(from: OverpassResponse.decode(data), syncedAt: runStarted)
        let hidden = rows.filter { $0.kind == nil }.count
        say("fixture: \(rows.count) rows (\(rows.count - hidden) shown, \(hidden) hidden)")
        exit(0)
    } catch {
        fail("fixture: \(error)")
    }
}

let env = ProcessInfo.processInfo.environment
let overpass = URL(string: env["OVERPASS_URL"] ?? "https://overpass-api.de/api/interpreter")!
var supabase: Supabase?
if !options.dryRun {
    guard let base = env["SUPABASE_URL"].flatMap(URL.init(string:)), !(env["SUPABASE_URL"] ?? "").isEmpty else {
        fail("SUPABASE_URL is not set")
    }
    guard let key = env["SUPABASE_SECRET_KEY"], !key.isEmpty else { fail("SUPABASE_SECRET_KEY is not set") }
    supabase = Supabase(base: base, key: key)
    // Check the key before the slow Overpass work: an empty box in the ocean changes nothing.
    do {
        _ = try await supabase!.markRemoved(in: BoundingBox(south: -0.001, west: -0.001, north: 0, east: 0),
                                             runStarted: "1970-01-01T00:00:00Z")
        say("Supabase write access: OK.")
    } catch {
        fail("Supabase write check failed. Check SUPABASE_URL and SUPABASE_SECRET_KEY (a sb_secret_ key). \(error)")
    }
}

let tiles = Array(options.region.tiles().prefix(options.maxTiles))
say("Region \(options.region.name): \(tiles.count) tiles. Run started \(runStartedText).\(options.dryRun ? " DRY RUN." : "")")

var totalRows = 0, totalHidden = 0, totalRemoved = 0
var failedTiles: [String] = []
for (i, tile) in tiles.enumerated() {
    let label = "tile \(i + 1)/\(tiles.count) [\(tile.south),\(tile.west) → \(tile.north),\(tile.east)]"
    do {
        if i > 0 { try await Task.sleep(nanoseconds: 5_000_000_000) } // be polite to Overpass
        let rows = try OSMSync.rows(from: try await fetchTile(tile, overpass: overpass), syncedAt: runStarted)
        var removed = 0
        if let supabase {
            try await supabase.upsert(rows)
            removed = try await supabase.markRemoved(in: tile, runStarted: runStartedText)
        }
        let hidden = rows.filter { $0.kind == nil }.count
        totalRows += rows.count; totalHidden += hidden; totalRemoved += removed
        say("\(label): \(rows.count) rows, \(hidden) hidden, \(removed) marked removed")
    } catch {
        // Keep the old data for this tile. It is tried again on the next run.
        failedTiles.append(label)
        say("\(label): FAILED, old data kept. \(error)")
    }
}

say("Done: \(totalRows) rows (\(totalHidden) hidden), \(totalRemoved) marked removed, \(failedTiles.count) failed tiles.")
exit(failedTiles.isEmpty ? 0 : 1)
