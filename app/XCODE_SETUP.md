# WaterFinder — Phase 1

A native iOS app (SwiftUI + MapKit) that shows public drinking water from OpenStreetMap.

## Requirements
- Xcode 15 or later
- iOS 17 or later (for the new SwiftUI Map API)

## Setup with XcodeGen (recommended)
1. Install XcodeGen one time: `brew install xcodegen`.
2. Optional: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`. Set your Team ID in it.
   If you skip this step, select your team under **Signing & Capabilities** after each generate.
3. In Terminal, go to the `app/` folder. Run `xcodegen`.
4. Open `WaterFinder.xcodeproj`. Select your iPhone. Run.

Run `xcodegen` again after you add, move, or delete files. Do not edit the `.xcodeproj` by hand.
Git does not track it. `project.yml` is the source of truth.

`project.yml` sets these items for you:
- iOS 17.0 deployment target, iPhone only.
- Location usage text: `Shows drinking water near you.`
- The local `WaterFinderCore` package (`../WaterFinderCore`).
- Swift 5 language mode with strict concurrency checks.

## Manual setup (fallback)
1. In Xcode, select **File > New > Project > iOS > App**.
2. Set Product Name to `WaterFinder`. Set Interface to **SwiftUI**. Set Storage to **None**.
3. Delete the `ContentView.swift` and `WaterFinderApp.swift` files that Xcode made.
4. Drag the `Models`, `Services`, and `Views` folders and `WaterFinderApp.swift` into the project.
   Select **Copy items if needed** and **Create groups**.
5. Select **File > Add Package Dependencies > Add Local**. Select the `WaterFinderCore` folder.
6. Select the target > **Info** tab. Add the key
   **Privacy - Location When In Use Usage Description** with the value
   `Shows drinking water near you.`
7. Set **Minimum Deployments** to iOS 17.0.
8. Select your iPhone and your personal team under **Signing & Capabilities**. Run.

## How it works
- `OverpassClient` sends one query to the public Overpass API for the visible area.
- `WaterSpotStore` loads data in 0.25° tiles and keeps a 7-day disk cache.
  Areas you loaded before still show with no signal.
- The map loads data only when the area is less than 1° wide. Zoom in if you see the message.
- `WaterSpotSource` is a protocol. Phase 2 adds a Supabase source with no change to the views.

## Caution
The public Overpass server has usage limits. This phase is for personal tests only.
Phase 2 moves the query to a backend sync, before other people use the app.

Keep the "© OpenStreetMap contributors" link. The ODbL license requires it.
