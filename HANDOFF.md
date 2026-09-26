# HANDOFF — Oasis

Date: 2026-09-25. Written at the end of a Claude.ai chat session, for the first Claude Code session.

## 1. Decisions Mike made
- Native iOS app: SwiftUI + MapKit (not a PWA).
- Data source: OpenStreetMap, plus community submissions.
- Users can sign up to contribute. Moderators review and approve submissions.
- Focus: cyclists first; through-hikers and long-distance walkers second.

## 2. Proposals not yet confirmed by Mike
These came from Claude, not from Mike. Confirm before you build on them.
- Backend: Supabase (Postgres + PostGIS, Auth, Storage, row-level security).
- Roles: contributor, moderator, admin.
- Spot status flow: pending → approved | rejected. Problem reports can send an approved spot back to review.
- Build phases:
  1. Read-only map of OSM water (done as a first draft).
  2. Accounts, submissions, moderator review.
  3. GPX route import, "distance to next water", offline download for a route.
  4. Photos, problem reports, optional upload to OSM with the user's own account.

## 3. Current state
### Repo setup (task 1) — DONE
- `.gitignore` for macOS, Xcode, and SwiftPM. It ignores `*.xcodeproj/` because XcodeGen (task 2) generates the project.
- `.github/workflows/pages.yml` deploys `tools/explorer/` to GitHub Pages on each push to `main` that changes the explorer. You can also run it by hand (workflow_dispatch).
- Pages URL: https://mikeheffler.github.io/Oasis/
- Mike must set Settings > Pages > Source to "GitHub Actions" one time.

### XcodeGen (task 2) — DONE, NOT RUN ON A MAC
- `app/project.yml` makes `Oasis.xcodeproj`. iOS 17, iPhone only, location usage text, Swift 5 mode with strict concurrency, local `OasisCore` package.
- `app/Config/Base.xcconfig` holds the bundle ID and team. It optionally includes `app/Config/Local.xcconfig` (not in git) for Mike's Team ID. See `Local.xcconfig.example`.
- The container has no Swift toolchain by default. Install Swift 6.1.2 for Ubuntu 24.04 from download.swift.org into `/opt/swift`, then add `/opt/swift/usr/bin` to `PATH`. A SessionStart hook could automate this.
- `app/XCODE_SETUP.md` now describes the XcodeGen steps first.

### OasisCore (task 3) — DONE
Swift package, Foundation only. `cd OasisCore && swift test` passes on Linux (Swift 6.1.2, 58 tests).
- `Coordinate` — own lat/lon type, haversine distance.
- `SpotKind`, `WaterSpot` — same Codable keys as the phase 1 disk cache.
- `OSMRules` — tag rules. Same rules as the explorer (the app still has its old copy until task 4).
- `BoundingBox`, `TileKey`, `Geo` — 0.25° tile math. `BoundingBox(covering:)` is now failable (nil for no tiles).
- `OverpassQuery` — box and `around` queries, `tags` or `meta` output, form-body encoding.
- `OverpassResponse` — parser. It throws `OverpassParseError.incomplete` when Overpass returns HTTP 200 with a runtime-error remark (timeout). The phase 1 app does not check this, so it can cache a partial tile as complete for 7 days. Task 4 fixes the app.
- `Route`, `RouteAnalysis` — ported from the explorer route check: projection, point at distance, slice, sampling for `around`, stops within a buffer, gaps, longest gaps, next stop.
- Fixtures in `OasisCore/Tests/OasisCoreTests/Fixtures/` are synthetic Overpass JSON.
- The route math was checked against the explorer JavaScript in Node with the same inputs. The numbers match.

Differences from the explorer (on purpose):
- The explorer shows hidden points as red markers. OasisCore drops them. `OSMRules.evaluate(_:)` gives the reason if a caller needs it.
- `Route.point(atDistance:)` clamps to the route ends. The explorer extrapolates.
- `Route.sampled` does not add the last point two times.
- The explorer does not check the Overpass `remark`.

Not ported yet: GPX parsing. On Linux, `XMLParser` is in `FoundationXML`. Add it with phase 3.

Until task 4, the app still has its own copies of this logic. The app does not import OasisCore yet.

### Buy water, problem tags, verification (OasisCore) — DONE
Mike's decisions (2026-09-26): two verification levels, hide problem tags, a separate "Buy water" category, OSM only for businesses.
- `SpotKind.buy` ("Buy water"). `SpotKind.isFree` is false only for `buy`.
- `OSMRules.evaluate(_:)` returns `.show(kind)` or `.hide(reason)`. It replaces `exclusion(for:)`.
- `VerificationRules` and `WaterSpot.verification(asOf:)`. Verified = `check_date` or `survey:date` within 24 months (whole UTC days). Accepts YYYY, YYYY-MM, YYYY-MM-DD, and `;` lists. Ignores future dates.
- `OverpassQuery.query(in:layers:)` with `.freeWater` and `.buyWater`. `waterPoints(in:)` is unchanged (free water only).
- 78 tests pass on Linux.

### app/Oasis (phase 1 draft) — NOT COMPILED
Written in chat with no Xcode. Expect small build errors.
- `Models/WaterSpot.swift` — `SpotKind`, `WaterSpot`, OSM tag classification.
- `Models/MapTiles.swift` — 0.25° tile grid, bounding boxes.
- `Services/OverpassClient.swift` — POST query to public Overpass (prototype only).
- `Services/WaterSpotStore.swift` — tile loading, 400 ms debounce, 7-day JSON disk cache.
- `Services/LocationManager.swift` — when-in-use location.
- `Services/WaterSpotSource.swift` — protocol so the backend can replace Overpass.
- `Views/MapScreen.swift` — Map with markers, filter chips, OSM attribution.
- `Views/SpotDetailSheet.swift` — details, warnings, directions, OSM link.
- `app/XCODE_SETUP.md` — manual Xcode setup steps.

Known risks to check on first Mac build:
- SF Symbol `spigot.fill` availability on iOS 17.
- Swift 6 / default-MainActor isolation warnings (Xcode 26 templates).
- `MKPlacemark` / `MKMapItem(placemark:)` deprecation on iOS 26; use the new `MKMapItem` initializer behind `#available`.

### tools/explorer/index.html — NOT RUN IN A BROWSER YET
Leaflet map with the same query and classification. Features: auto-load by view, filter chips with counts, color by last update, data-quality stats, GPX route check (water within a buffer, three longest gaps), GeoJSON export, locate button. It cannot run inside claude.ai artifacts (network blocked). It must be hosted (GitHub Pages).

### Validation status
Mike has not yet validated OSM coverage. Plan: use Overpass Turbo on his phone, export GeoJSON for Napa County and for his own ride areas, and compare to real-world knowledge. The original trigger was a cycling trip in Napa Valley with very few public refill points.

## 4. First tasks for Claude Code (in order)
1. **Repo setup.** Add `.gitignore` for Xcode/Swift, and a GitHub Actions workflow that deploys `tools/explorer/` to GitHub Pages. Tell Mike the Pages URL and the one repo setting he must change (Settings > Pages > Source: GitHub Actions).
2. **XcodeGen.** Add `app/project.yml` so Mike can run `xcodegen` on his Mac instead of the manual steps. Include the location usage string, iOS 17 target, and the local `OasisCore` package dependency.
3. **OasisCore package.** Move pure logic out of the app into `OasisCore/` (Foundation only, no CoreLocation/MapKit): own `Coordinate` type, `SpotKind`, classification, tile math, Overpass query builder, Overpass JSON parser, route distance and gap analysis (port from the explorer's JS). Add unit tests with fixture JSON. Run `swift test` here on Linux.
4. **Refactor app** to use `OasisCore`. Keep app code thin.
5. **Phase 2 design doc** in `docs/phase2-backend.md` for Mike to approve before any backend code: schema, RLS policies, auth, sync job, moderation flow (outline below).

## 5. Phase 2 outline (proposal)
- Tables: `osm_water_points` (synced, read-only), `community_spots` (status, submitted_by, reviewed_by, review_note), `spot_reports` (type: working, not_working, seasonal_off, refused, not_potable, other), `spot_photos`, `profiles` (role).
- PostGIS `geography(Point)` columns with GiST indexes. RPCs: `spots_in_bbox`, `spots_near_route(line, buffer_m)`.
- RLS: anyone reads approved spots; signed-in users insert pending spots and reports; only moderators change status. Enforce with a `is_moderator()` SQL function.
- Auth: Sign in with Apple (App Store rules require it if any social login exists) plus email magic link.
- OSM sync: scheduled job (GitHub Action or Supabase Edge Function) that queries Overpass by region and upserts. Start with regions Mike rides.
- Moderator console: start inside the iOS app behind the moderator role; a web console can come later.

## 6. Open questions for Mike
- Confirm Supabase and the roles above.
- Which regions to sync first?
- App Store release, TestFlight only, or personal use?
- App name: decided. Mike renamed the app to "Oasis" on 2026-09-26.
