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

### Sync fix after the first live run (2026-09-30)
- Run 3 (1° tiles) saved 0 rows in 26 minutes. A test from the dev container got `504 ... Dispatcher_Client::request_read_and_idx::timeout. The server is probably too busy` from overpass.kumi.systems after 103 s. Each failed tile cost about 6 minutes of retries, so the run could not finish in its 120-minute limit (and the old tool's buffered output would be lost on a time-out).
- Fix: 0.5° tiles (150 for Colorado), requested Overpass timeout 120 s, retries after 30 s and 60 s that move to the next server in `OVERPASS_URLS`, job limit 240 minutes. Each tile is saved as soon as it arrives, so a stopped run keeps its finished tiles.
- Run 4 stopped at the write check after 1 minute: `NSURLErrorDomain -1002 unsupported URL`. The `SUPABASE_URL` secret has no `https://` (the only form that gets past `URL(string:)` and then fails). Fix: `SupabaseSpotsAPI.projectURL(from:)` trims the text, adds `https://` when it is missing, and converts a dashboard link to `https://<ref>.supabase.co`. The tool prints the project host at start. 2 new tests, 119 total.
- Run 5 then failed with `Could not resolve host`. CI masked the host, so the secret is a bare host name, most likely the project ref alone. `projectURL(from:)` now also accepts a bare 20-character ref. The tool logs only the form of the URL (scheme, `.supabase.co` suffix, host length), not the value.
- Run 6 (after Mike fixed `SUPABASE_URL` to the full https URL) failed in the migration job: `supabase/setup-cli` could not resolve `version: latest` (GitHub API rate limit). Both workflows now pin CLI 2.118.0. Update the pin by hand when needed.
- **Run 7: first full Colorado sync (2026-09-30, 3 h 16 min).** 15,215 rows (31 hidden): restaurant 10,127, convenience 3,561, grocery 663, fountain 610, other 178, tap 34. 11 of 150 tiles failed (504 / 429 / time-outs on both servers), for example tile 96 (Castle Rock / Parker). Downtown Denver (tile 97, 4,592 rows) is in. Fix: 10 s between tiles (5 s gave many 429s), and a second pass for the failed tiles after a 2-minute pause. The final log line lists the tiles that still failed.
- **Run 8: complete Colorado sync (2026-10-01, 2 h 43 min), CI green.** 15,925 rows (35 hidden), 19 marked removed (gone from OSM since run 7), 0 failed tiles. The first pass had 2 failed tiles; the second pass fixed both. Live totals: restaurant 10,602, convenience 3,745, grocery 693, fountain 639, other 183, tap 36. The weekly cron (Monday 09:17 UTC) now keeps it current.
- Next: Mike checks the app in the Simulator at Denver (39.74, -104.99). Then step 2.4.

### Phase 2, step 2.3: app reads from the backend — DONE (PR pending), NOT RUN ON A DEVICE
- `OasisCore/Sources/OasisCore/SupabaseSpots.swift`: `SupabaseSpotsAPI` (request body, split of a box into ≤ 0.5° pieces, parser for `spots_in_bbox` rows, PostgREST timestamp parser, truncation flag at 5000 rows), `BoundingBox.intersects`, `SyncRegion.coverage(includes:)`. `WaterSpot.lastReport` (type + date) for step 2.4; optional, so old caches decode. 9 new tests, 116 total.
- App: `Services/SupabaseConfig.swift` (project URL + publishable key, both public) and `DataSources.makeDefault()` (backend; debug builds use Overpass when the scheme sets `OASIS_SOURCE=overpass`). `Services/SupabaseSource.swift` (plain `URLSession` POST to `rest/v1/rpc/spots_in_bbox` with the `apikey` header; no supabase-swift yet — it comes with sign-in in 2.5). The store shows "Oasis has data for Colorado only for now." outside the synced regions. Cache file `water-spots-cache-v5.json`.
- Checked live: `SupabaseSource` requests from Linux against the real project return HTTP 200 and parse (0 rows until the first sync finishes). A 3° box is split correctly (the server rejects > 2°).
- `oasis-sync`: unbuffered output (CI logs show progress during a run), and a write check with the secret key before the Overpass work (a wrong key stops the run at once; checked with the publishable key → "permission denied").

### Phase 2, step 2.2: Colorado OSM sync — SECRETS ADDED, MIGRATIONS APPLIED (2026-09-30)
- `OasisCore/Sources/OasisCore/OSMSync.swift`: `SyncRegion` (Colorado: 150 tiles of 0.5°, see the fix below), `OSMPointRow` (one `osm_points` row, EWKT geometry, explicit `removed_at: null`), `OSMSync.rows(from:syncedAt:)` (same `OSMRules`; keeps hidden points with the reason; throws on an incomplete Overpass reply). 8 new tests, 107 total.
- `OasisCore/Sources/oasis-sync/main.swift`: command-line tool. Per tile: Overpass (5 s apart, 2 retries), upsert in batches of 500 through PostgREST with the secret key in the `apikey` header, then `mark_removed_osm_points`. A failed tile keeps its old data, and the run exits 1. `--dry-run`, `--max-tiles N`, `--fixture file`.
- `supabase/migrations/20260927000000_osm_sync.sql`: `mark_removed_osm_points` (service role only) + `supabase/tests/osm_sync.test.sql` (9 tests).
- `.github/workflows/backend.yml`: applies migrations on merge (`supabase db push --db-url`), and syncs every Monday 09:17 UTC or from "Run workflow" (region, tile limit, migrate-only).
- Not yet run against the live project: needs the secrets `SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `SUPABASE_DB_URL`. Overpass is blocked from the dev container, so the first real sync is the GitHub Action.
- Publishable key received and checked (see docs/phase2-backend.md, section 13).

### Phase 2, step 2.1: database schema — DONE (PR pending)
- `supabase/config.toml` (CLI settings) and `supabase/migrations/20260926230000_phase2_schema.sql`: PostGIS, `profiles`, `osm_points`, `community_spots`, `spot_reports`, GiST indexes, a profile for each new account, `is_moderator()`, anti-spam limits (1 report per person per point per hour, 20 submissions per day), review stamping, and the `spots_in_bbox` read function (max 2° box, 5000 rows, never returns reporter or submitter).
- Privileges: the migration revokes Supabase's default table grants and grants only the columns the API needs. RLS on all four tables.
- `supabase/tests/phase2_schema.test.sql`: 39 pgTAP tests (anon, two contributors, a moderator). CI job `Database tests (Supabase)` runs them with `supabase db start` + `supabase test db`.
- Applied to the live project by the Backend workflow (step 2.2), once `SUPABASE_DB_URL` exists.
- Kind values are in three places now: `OasisCore` `SpotKind`, the explorer, and the SQL check constraints and `spots_in_bbox`. Change all together.

### CI (step 0) — DONE, GREEN
- `.github/workflows/ci.yml` runs on every PR and on pushes to `main`:
  - `OasisCore tests (Linux)` in the `swift:6.1` container.
  - `iOS app build (macOS)` on `macos-15`: `swift test` for OasisCore, then `xcodegen` and `xcodebuild` for the iOS Simulator with no code signing. The last step lists all compiler errors and warnings.
  - First run (PR #19): BUILD SUCCEEDED with Xcode 16.4 / iOS 18.5 SDK, strict concurrency on, zero Swift errors or warnings. Mike may use a newer Xcode locally; new SDK deprecations can show there first.
- Mike's decisions (2026-09-26): phase 2 (backend) before phase 3, Supabase, own phone first (no Apple Developer Program yet), first sync region is the state of Colorado.

### XcodeGen (task 2) — DONE, NOT RUN ON A MAC
- `app/project.yml` makes `Oasis.xcodeproj`. iOS 17, iPhone only, location usage text, Swift 5 mode with strict concurrency, local `OasisCore` package.
- `app/Config/Base.xcconfig` holds the bundle ID and team. It optionally includes `app/Config/Local.xcconfig` (not in git) for Mike's Team ID. See `Local.xcconfig.example`.
- The container has no Swift toolchain by default. Install Swift 6.1.2 for Ubuntu 24.04 from download.swift.org into `/opt/swift`, then add `/opt/swift/usr/bin` to `PATH`. A SessionStart hook could automate this.
- `app/XCODE_SETUP.md` now describes the XcodeGen steps first.

### OasisCore (task 3) — DONE
Swift package, Foundation only. `cd OasisCore && swift test` passes on Linux (Swift 6.1.2, 58 tests).
- `Coordinate` — own lat/lon type, haversine distance.
- `SpotKind`, `WaterSpot` — same Codable keys as the phase 1 disk cache.
- `OSMRules` — tag rules. Same rules as the explorer.
- `BoundingBox`, `TileKey`, `Geo` — 0.25° tile math. `BoundingBox(covering:)` is now failable (nil for no tiles).
- `OverpassQuery` — box and `around` queries, `tags` or `meta` output, form-body encoding.
- `OverpassResponse` — parser. It throws `OverpassParseError.incomplete` when Overpass returns HTTP 200 with a runtime-error remark (timeout). The app uses this since task 4, so it no longer caches a partial tile.
- `Route`, `RouteAnalysis` — ported from the explorer route check: projection, point at distance, slice, sampling for `around`, stops within a buffer, gaps, longest gaps, next stop.
- Fixtures in `OasisCore/Tests/OasisCoreTests/Fixtures/` are synthetic Overpass JSON.
- The route math was checked against the explorer JavaScript in Node with the same inputs. The numbers match.

Differences from the explorer (on purpose):
- The explorer shows hidden points as red markers. OasisCore drops them. `OSMRules.evaluate(_:)` gives the reason if a caller needs it.
- `Route.point(atDistance:)` clamps to the route ends. The explorer extrapolates.
- `Route.sampled` does not add the last point two times.
- The explorer does not check the Overpass `remark`.

Not ported yet: GPX parsing. On Linux, `XMLParser` is in `FoundationXML`. Add it with phase 3.

### Buy water, problem tags, verification (OasisCore) — DONE
Mike's decisions (2026-09-26): two verification levels, hide problem tags, a separate "Buy water" category, OSM only for businesses.
- Buy water kind (split into three categories later, see below). `SpotKind.isFree` is false only for buy kinds.
- `OSMRules.evaluate(_:)` returns `.show(kind)` or `.hide(reason)`. It replaces `exclusion(for:)`.
- `VerificationRules` and `WaterSpot.verification(asOf:)`. Verified = `check_date` or `survey:date` within 24 months (whole UTC days). Accepts YYYY, YYYY-MM, YYYY-MM-DD, and `;` lists. Ignores future dates.
- `OverpassQuery.query(in:layers:)` with `.freeWater` and `.buyWater`. `waterPoints(in:)` is unchanged (free water only).
- 78 tests pass on Linux.

### Buy water on the map, clustering (OasisCore) — DONE
Mike's decision (2026-09-26): show buy water on the map with a toggle, and group dense points into one icon with a count.
- `SpotLayer` (`freeWater`, `buyWater`) and `SpotKind.layer`. `OverpassQuery.Layer` is now a typealias for `SpotLayer`.
- `TileCache` — spots plus tile load times per layer. `merge` replaces one layer in the given tiles and keeps only spots of that layer's kinds. The app store uses it.
- `SpotClustering` — grid clustering in Web Mercator space. Cell size is 360/2^n degrees, about 8 cells across the view. Free and buy water cluster separately. A cell needs 3 or more spots to become a cluster.
- 95 tests pass on Linux.

### Buy water categories and on-map counts — DONE (OasisCore + explorer)
Mike's decision (2026-09-26): split buy water into three filterable categories, and show the active categories with counts on the map.
- `SpotKind.buy` is replaced by `.convenience` ("Gas & convenience", incl. fuel and drink machines), `.grocery` (supermarket), and `.restaurant` ("Restaurant & cafe"). `SpotKind.buyKinds` lists them. `OSMRules.buyKind(_:)` picks the category.
- Restaurant & cafe is off by default (largest group, least useful for a quick stop).
- Explorer: "In view" legend box on the map (top right). It lists only categories that are on and have points in the view, with counts ("No points in view" when empty). It stays visible when the side panel is hidden. Markers: all buy categories are deep amber (#A8650A, 4.6:1 with white) and differ by symbol: fuel pump, cart, fork and knife.
- Parity check (43 tag cases, dates, query text) matched. 99 tests pass.

### app/Oasis (phase 1, uses OasisCore since task 4) — BUILDS IN CI, NOT RUN ON A DEVICE YET
CI builds it for the iOS Simulator on every PR. Nobody has run it on a device yet.
The app has no logic of its own now. The logic is in OasisCore.
- `Models/CoreBridges.swift` — `Coordinate` ↔ `CLLocationCoordinate2D`, `BoundingBox(MKCoordinateRegion)`, region contains.
- `Models/SpotKind+Style.swift` — SF Symbols and the shared colors (`Color.oasisBlue` #1668C7, `.oasisAmber` #A8650A, `.oasisSlate` #5E6E7C), same as the explorer. Buy categories: `fuelpump.fill`, `cart.fill`, `fork.knife`.
- `Views/SpotPin.swift` — the map pin: 28 pt round badge, white SF Symbol, white border, shadow, check-mark badge for verified points (44 pt tap area). Same design as the explorer. Mike wants to revisit the branding later; change it here.
- `Services/OverpassClient.swift` — uses `OverpassQuery` and `OverpassResponse`. A timeout remark throws, so the tile is not cached. Type-checked on Linux against OasisCore.
- `Services/WaterSpotStore.swift` — per-layer tile loading with `TileCache`, 400 ms debounce, 7-day JSON disk cache (`water-spots-cache-v4.json`). Buy water loads when a buy category chip is on and the view is at most 0.5° wide. Type-checked on Linux with stand-ins for the two MapKit types.
- `Services/LocationManager.swift` — when-in-use location.
- `Services/WaterSpotSource.swift` — `Sendable` protocol so the backend can replace Overpass. Type-checked on Linux.
- `Views/MapScreen.swift` — `SpotPin` annotations (no fading; verified has a check mark), numbered cluster badges from `SpotClustering` (tap to zoom; off below 0.01° wide), filter chips with the count in view for each kind (Restaurant & cafe off by default), "Verified only" chip, OSM attribution.
- `Views/SpotDetailSheet.swift` — verification state, details, warnings (business, buy, seasonal), directions, OSM link.
- `app/XCODE_SETUP.md` — XcodeGen and manual setup steps.

Known risks to check on first Mac build:
- SF Symbol `spigot.fill` availability on iOS 17.
- Swift 6 / default-MainActor isolation warnings (Xcode 26 templates).
- `MKPlacemark` / `MKMapItem(placemark:)` deprecation on iOS 26; use the new `MKMapItem` initializer behind `#available`.

### tools/explorer/index.html — LIVE on GitHub Pages
- Base map: OSM standard, plus CyclOSM in the layer menu. CARTO was removed (it needs an API key on public hosts).
- Same rules as OasisCore: buy water, problem tags, and verification. A parity check (35 tag cases, 13 date strings, both query texts) matched the Swift code.
- Buy water has a chip (on by default). It loads in the map view when the view is at most 0.5° wide, and along a GPX route. Close points group into numbered clusters (Leaflet.markercluster 1.5.3, blue for free water, amber for buy water). A "Group close points" checkbox turns grouping off. The explorer uses the plugin's pixel-radius clustering, not `SpotClustering`, so cluster edges differ slightly from the app. Points are 28 px icon badges (solid color, white symbol, white border, shadow); a small check-mark badge marks a verified point. The app uses the same pin design (`SpotPin`). "Verified only" filter. Hidden points show their reason in the popup.
- Layout: the panel is a side menu. A menu button (sliders icon) on the map opens and closes it. On phones (≤760 px) it slides in over the map and is closed by default (close with ✕, the dimmed map, or Escape; picking a search result or route item closes it). On larger screens it is docked on the left and open by default; closing it gives the map the full width.
- Loading card in the center of the map: a water bottle that fills (with a moving wave) and the percent in blue below it. Overpass does not report progress, so the percent is an estimate: it eases toward 70% while the server works, follows the downloaded bytes, and reaches 100% when the data is ready. With two queries (free + buy water), each is half. The wave stops when the device asks for reduced motion.
- Tested in headless Chromium with the fixture as a mock Overpass response. Mike tested the live page in Chrome.

Earlier notes:
Leaflet map with the same query and classification. Features: auto-load by view, filter chips with counts, color by last update, data-quality stats, GPX route check (water within a buffer, three longest gaps), GeoJSON export, locate button. It cannot run inside claude.ai artifacts (network blocked). It must be hosted (GitHub Pages).

### Validation status
Mike has not yet validated OSM coverage. Plan: use Overpass Turbo on his phone, export GeoJSON for Napa County and for his own ride areas, and compare to real-world knowledge. The original trigger was a cycling trip in Napa Valley with very few public refill points.

## 4. First tasks for Claude Code (in order)
1. **Repo setup.** Add `.gitignore` for Xcode/Swift, and a GitHub Actions workflow that deploys `tools/explorer/` to GitHub Pages. Tell Mike the Pages URL and the one repo setting he must change (Settings > Pages > Source: GitHub Actions).
2. **XcodeGen.** Add `app/project.yml` so Mike can run `xcodegen` on his Mac instead of the manual steps. Include the location usage string, iOS 17 target, and the local `OasisCore` package dependency.
3. **OasisCore package.** Move pure logic out of the app into `OasisCore/` (Foundation only, no CoreLocation/MapKit): own `Coordinate` type, `SpotKind`, classification, tile math, Overpass query builder, Overpass JSON parser, route distance and gap analysis (port from the explorer's JS). Add unit tests with fixture JSON. Run `swift test` here on Linux.
4. **Refactor app** to use `OasisCore`. Keep app code thin.
5. **Phase 2 design doc** in `docs/phase2-backend.md` for Mike to approve before any backend code: schema, RLS policies, auth, sync job, moderation flow. DRAFT WRITTEN (2026-09-26), waiting for Mike's review.

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
