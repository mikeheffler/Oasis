import CoreLocation
import MapKit
import OasisCore

// Conversions between OasisCore types (Foundation only) and Apple frameworks.

extension Coordinate {
    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension WaterSpot {
    var clCoordinate: CLLocationCoordinate2D { coordinate.clCoordinate }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

extension BoundingBox {
    init(_ region: MKCoordinateRegion) {
        self.init(center: Coordinate(region.center),
                  latitudeDelta: region.span.latitudeDelta,
                  longitudeDelta: region.span.longitudeDelta)
    }
}

extension MKCoordinateRegion {
    /// True if the point is in the region, with a small margin.
    func contains(_ c: Coordinate, margin: Double = 1.2) -> Bool {
        abs(c.latitude - center.latitude) <= span.latitudeDelta / 2 * margin &&
        abs(c.longitude - center.longitude) <= span.longitudeDelta / 2 * margin
    }
}
