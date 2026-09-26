import SwiftUI
import MapKit

struct MapScreen: View {
    @State private var store = WaterSpotStore(source: OverpassClient())
    @State private var location = LocationManager()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var enabledKinds = Set(SpotKind.allCases)

    /// More markers than this makes the map slow, so show the nearest ones.
    private let markerLimit = 400

    var body: some View {
        Map(position: $position, selection: $selectedID) {
            UserAnnotation()
            ForEach(visibleSpots) { spot in
                Marker(spot.displayName, systemImage: spot.kind.symbol, coordinate: spot.coordinate)
                    .tint(spot.kind.tint)
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
        let all = store.spots.values.filter { enabledKinds.contains($0.kind) }
        guard let region = visibleRegion else { return Array(all.prefix(markerLimit)) }
        let inView = all.filter { region.contains($0.coordinate) }
        guard inView.count > markerLimit else { return inView }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        return Array(inView
            .sorted { center.distance(from: $0.location) < center.distance(from: $1.location) }
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
    let isLoading: Bool
    let statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpotKind.allCases) { kind in
                        chip(for: kind)
                    }
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
