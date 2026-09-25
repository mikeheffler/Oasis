# WaterFinder — Phase 1

A native iOS app (SwiftUI + MapKit) that shows public drinking water from OpenStreetMap.

## Requirements
- Xcode 15 or later
- iOS 17 or later (for the new SwiftUI Map API)

## Setup
1. In Xcode, select **File > New > Project > iOS > App**.
2. Set Product Name to `WaterFinder`. Set Interface to **SwiftUI**. Set Storage to **None**.
3. Delete the `ContentView.swift` and `WaterFinderApp.swift` files that Xcode made.
4. Drag the `Models`, `Services`, and `Views` folders and `WaterFinderApp.swift` into the project.
   Select **Copy items if needed** and **Create groups**.
5. Select the target > **Info** tab. Add the key
   **Privacy - Location When In Use Usage Description** with the value
   `Shows drinking water near you.`
6. Set **Minimum Deployments** to iOS 17.0.
7. Select your iPhone and your personal team under **Signing & Capabilities**. Run.

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
