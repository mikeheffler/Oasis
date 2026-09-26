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
- OSM query tags: `amenity=drinking_water`, `amenity=water_point`, `man_made=water_tap` + `drinking_water=yes`, any feature with `drinking_water=yes`, and `drinking_water:refill=yes` (businesses in the Refill scheme).
- Exclude `drinking_water=no` and `access` in {private, no, customers}.
- The classification rules exist in two places: `app/.../WaterSpot.swift` and `tools/explorer/index.html`. When you move them into `OasisCore`, keep the explorer in sync or note the difference.
- ODbL license: keep OSM data and community data in separate tables and layers. Do not bulk-upload community data to OSM. Any future OSM upload goes through each user's own OSM account.
- Respect the Overpass usage policy. Clients must not query the public Overpass server in production. The backend syncs OSM data on a schedule.

## Workflow
- Work on a branch per task and open a PR. Keep PRs small.
- Add or update tests in `OasisCore` for every logic change.
- Update HANDOFF.md "Current state" when a task finishes.
