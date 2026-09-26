# CLAUDE.md — Oasis

## What this is
A native iOS app (SwiftUI + MapKit, iOS 17+) that shows public drinking water: fountains, taps/spigots, and businesses that give water to people passing through. Primary users: cyclists on long rides, then through-hikers and long-distance walkers who travel through populated areas with no filterable water.

The owner is Mike. He is a physician and an experienced hobby developer (Python, Node, React PWAs, SQL). He builds production-quality tools, not throwaway prototypes. He writes Swift less often, so explain Swift-specific choices briefly.

## Communication
Mike prefers ASD-STE100 Simplified Technical English: short sentences, one instruction per sentence, active voice, common words. Apply this to messages to Mike, PR descriptions, and commit summaries. Code comments can be normal technical English but stay short.

## Environment limits (important)
- This session runs on Linux. There is no Xcode and no iOS SDK. You cannot build or run the iOS app here.
- Keep all testable logic in the `OasisCore` Swift package (see HANDOFF.md). It must import only Foundation, so it builds and tests on Linux with `swift build` / `swift test`.
- SwiftUI, MapKit, and CoreLocation code lives in `app/` and is built by Mike on his Mac. Mark any code you could not compile with a `// UNVERIFIED: not compiled` note in the PR description, not in the code.
- The container network may block overpass-api.de and openstreetmap.org. Do not depend on live OSM calls in tests. Use fixture JSON files in `OasisCore/Tests/Fixtures/`.

## Conventions
- Swift 5.10+ language mode, strict concurrency warnings on. Views and stores are `@MainActor`. Models are value types and `Sendable`.
- Use `@Observable` (Observation framework), not `ObservableObject`.
- No third-party dependencies in the app except `supabase-swift` (phase 2). No analytics SDKs, no ads.
- Colors: blue = public water, amber = businesses (ask first), slate = other, red = problems only. Keep the palette small.
- Units follow the device locale; Mike uses miles.
- Keep the "© OpenStreetMap contributors" attribution visible on every map.

## Data rules
- Free water query tags: `amenity=drinking_water`, `amenity=water_point`, `man_made=water_tap` + `drinking_water=yes`, any feature with `drinking_water=yes`, and `drinking_water:refill=yes` (businesses in the Refill scheme).
- "Buy water" has three categories (Mike's decision, 2026-09-26), each with its own filter: `convenience` "Gas & convenience" (`shop` in {convenience, general, kiosk}, `amenity=fuel`, drink vending machines), `grocery` (`shop=supermarket`), and `restaurant` "Restaurant & cafe" (`amenity` in {restaurant, cafe, fast_food}; off by default). Order for mixed tags: grocery, then convenience, then restaurant. All three are the `buyWater` layer. The map view loads it only when the view is at most 0.5° wide and a buy category is on; the route check loads it along the route. Dense points group into numbered clusters (`SpotClustering`), free and buy water separately. Use OSM only for businesses for now.
- Hide `drinking_water=no`, `access` in {private, no, customers}, and problem tags (`operational_status` broken/closed/out of order, `disused=yes`, `abandoned=yes`). Exception: a place that sells drinks stays in its buy category with `access=customers` or `drinking_water=no`.
- Two verification levels only: verified (OSM `check_date` or `survey:date` in the last 24 months; phase 2 adds Oasis user reports) and unverified (everything else). Show unverified points; do not hide them.
- The rules live in `OasisCore` (`OSMRules`, `VerificationRules`) and in `tools/explorer/index.html`. Change both together, or note the difference in HANDOFF.md.
- ODbL license: keep OSM data and community data in separate tables and layers. Do not bulk-upload community data to OSM. Any future OSM upload goes through each user's own OSM account.
- Respect the Overpass usage policy. Clients must not query the public Overpass server in production. The backend syncs OSM data on a schedule.

## Workflow
- Work on a branch per task and open a PR. Keep PRs small.
- Add or update tests in `OasisCore` for every logic change.
- Update HANDOFF.md "Current state" when a task finishes.
