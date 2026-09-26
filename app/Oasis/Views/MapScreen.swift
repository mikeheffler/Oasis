import SwiftUI
import MapKit
import OasisCore

struct MapScreen: View {
    @State private var store = WaterSpotStore(source: OverpassClient())
    @State private var location = LocationManager()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var enabledKinds = Set(SpotKind.mapKinds)
    @State private var verifiedOnly = false

    /// More markers than this makes the map slow, so show the nearest ones.
    private let markerLimit = 400

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(visibleSpots) { spot in
                // Unverified points are faded.
                Marker(spot.displayName, systemImage: spot.kind.symbol, coordinate: spot.clCoordinate)
                    .tint(spot.kind.tint.opacity(spot.verification() == .verified ? 1 : 0.55))
                    .tag(spot.id)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            store.regionChanged(context.region)
        }
        .safeAreaInset(edge: .top) {
            FilterBar(enabledKinds: $enabledKinds,
                      verifiedOnly: $verifiedOnly,
                      isLoading: store.isLoading,
                      statusMessage: store.statusMessage)
        }
        .sheet(item: selectedSpot) { spot in
            SpotDetailSheet(spot: spot, userLocation: location.lastLocation)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { location.start() }
    }

    private var visibleSpots: [WaterSpot] {
        let now = Date()
        let all = store.spots.values.filter {
            enabledKinds.contains($0.kind) && (!verifiedOnly || $0.verification(asOf: now) == .verified)
        }
        guard let region = visibleRegion else { return Array(all.prefix(markerLimit)) }
        let inView = all.filter { region.contains($0.coordinate) }
        guard inView.count > markerLimit else { return inView }
        let center = Coordinate(region.center)
        return Array(inView
            .sorted { center.distance(to: $0.coordinate) < center.distance(to: $1.coordinate) }
            .prefix(markerLimit))
    }

    private var selectedSpot: Binding<WaterSpot?> {
        Binding(
            get: { selectedID.flatMap { store.spots[$0] } },
            set: { selectedID = $0?.id }
        )
    }
}

private struct FilterBar: View {
    @Binding var enabledKinds: Set<SpotKind>
    @Binding var verifiedOnly: Bool
    let isLoading: Bool
    let statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpotKind.mapKinds) { kind in
                        chip(for: kind)
                    }
                    verifiedChip
                    if isLoading {
                        ProgressView().padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                Link("© OpenStreetMap contributors",
                     destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var verifiedChip: some View {
        Button {
            verifiedOnly.toggle()
        } label: {
            Label("Verified only", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(verifiedOnly ? Color.white : Color.primary)
                .background(verifiedOnly ? Color.primary.opacity(0.8) : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows only points surveyed in the last \(VerificationRules.windowMonths) months.")
        .accessibilityAddTraits(verifiedOnly ? .isSelected : [])
    }

    private func chip(for kind: SpotKind) -> some View {
        let isOn = enabledKinds.contains(kind)
        return Button {
            if isOn { enabledKinds.remove(kind) } else { enabledKinds.insert(kind) }
        } label: {
            Label(kind.label, systemImage: kind.symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? kind.tint : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#Preview {
    MapScreen()
}
