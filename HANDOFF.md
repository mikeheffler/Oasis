# HANDOFF — WaterFinder

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
### app/WaterFinder (phase 1 draft) — NOT COMPILED
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
2. **XcodeGen.** Add `app/project.yml` so Mike can run `xcodegen` on his Mac instead of the manual steps. Include the location usage string, iOS 17 target, and the local `WaterFinderCore` package dependency.
3. **WaterFinderCore package.** Move pure logic out of the app into `WaterFinderCore/` (Foundation only, no CoreLocation/MapKit): own `Coordinate` type, `SpotKind`, classification, tile math, Overpass query builder, Overpass JSON parser, route distance and gap analysis (port from the explorer's JS). Add unit tests with fixture JSON. Run `swift test` here on Linux.
4. **Refactor app** to use `WaterFinderCore`. Keep app code thin.
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
- App name ("WaterFinder" is a working name; other apps use similar names).
