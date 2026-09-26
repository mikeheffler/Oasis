import SwiftUI
import MapKit
import OasisCore

struct SpotDetailSheet: View {
    let spot: WaterSpot
    let userLocation: CLLocation?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(spot.kind.longLabel, systemImage: spot.kind.symbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(spot.kind.tint)
                        Text(spot.displayName)
                            .font(.title2.weight(.semibold))
                        if let distance {
                            Text(distance + " away")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        verificationLabel
                    }
                    .padding(.vertical, 4)

                    Button {
                        openDirections()
                    } label: {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.body.weight(.semibold))
                    }
                }

                if let warning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(red: 0.70, green: 0.40, blue: 0.00))
                    }
                }

                Section("Details") {
                    row("Bottle filler", spot.hasBottleFiller ? "Yes" : nil)
                    row("Seasonal", spot.seasonal)
                    row("Hours", spot.openingHours)
                    row("Fee", spot.fee)
                    row("Access", spot.access)
                    row("Last checked", spot.lastChecked)
                    row("Note", spot.note)
                    if !hasAnyDetail {
                        Text("No more details in OpenStreetMap.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let url = spot.osmURL {
                    Section {
                        Link("View or edit on OpenStreetMap", destination: url)
                    } footer: {
                        Text("Data from OpenStreetMap can be out of date. Always examine the water before you depend on it.")
                            .font(.footnote)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var verificationLabel: some View {
        if spot.verification() == .verified {
            Label("Verified: surveyed in the last \(VerificationRules.windowMonths) months",
                  systemImage: "checkmark.seal.fill")
                .font(.subheadline)
        } else {
            Label("Unverified: no survey in the last \(VerificationRules.windowMonths) months",
                  systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var hasAnyDetail: Bool {
        spot.hasBottleFiller || [spot.seasonal, spot.openingHours, spot.fee, spot.access, spot.lastChecked, spot.note]
            .contains { $0 != nil }
    }

    private var warning: String? {
        if spot.kind == .business { return "This is a business. Ask the staff before you fill your bottle." }
        if !spot.kind.isFree { return "You must buy water here. Check the opening hours." }
        if spot.seasonal != nil { return "This water can be off for part of the year." }
        return nil
    }

    private var distance: String? {
        guard let userLocation else { return nil }
        let meters = userLocation.distance(from: spot.location)
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value)
        }
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
        item.name = spot.displayName
        item.openInMaps()
    }
}
