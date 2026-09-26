import Foundation

/// Several close spots of one layer, shown as one numbered icon.
public struct SpotCluster: Identifiable, Hashable, Sendable {
    public let id: String
    public let layer: SpotLayer
    /// Mean position of the members.
    public let center: Coordinate
    public let count: Int
    /// The smallest box that holds all members. Zoom to it when the user taps the cluster.
    public let bounds: BoundingBox
}

public enum ClusterItem: Identifiable, Hashable, Sendable {
    case spot(WaterSpot)
    case cluster(SpotCluster)

    public var id: String {
        switch self {
        case .spot(let s): s.id
        case .cluster(let c): c.id
        }
    }
}

/// Grid clustering in Web Mercator space, so cells are square on screen at any latitude.
/// The grid is fixed to the world, not to the view, so clusters do not jump when the map pans.
public enum SpotClustering {
    /// A cell size in degrees of longitude for a view `longitudeSpan` wide, about
    /// `cellsAcross` cells across. Rounded to 360 / 2^n, so small zoom changes keep the same grid.
    public static func cellSize(forLongitudeSpan longitudeSpan: Double, cellsAcross: Int = 8) -> Double {
        let raw = max(longitudeSpan, 1e-9) / Double(max(cellsAcross, 1))
        let n = max(0, floor(log2(360 / raw)))
        return 360 / pow(2, n)
    }

    /// Groups spots that share a grid cell and a layer. A cell with fewer than
    /// `minClusterSize` spots shows its spots one by one. The output is sorted by id.
    public static func cluster(_ spots: some Sequence<WaterSpot>, cellSize: Double,
                               minClusterSize: Int = 3) -> [ClusterItem] {
        let cellsPerWorld = 360 / cellSize
        var cells: [CellKey: [WaterSpot]] = [:]
        for spot in spots {
            let (mx, my) = mercator(spot.coordinate)
            let key = CellKey(layer: spot.kind.layer,
                          x: Int((mx * cellsPerWorld).rounded(.down)),
                          y: Int((my * cellsPerWorld).rounded(.down)))
            cells[key, default: []].append(spot)
        }

        var items: [ClusterItem] = []
        for (key, members) in cells {
            guard members.count >= max(minClusterSize, 2) else {
                items += members.map(ClusterItem.spot)
                continue
            }
            let lats = members.map(\.latitude), lons = members.map(\.longitude)
            let n = Double(members.count)
            items.append(.cluster(SpotCluster(
                id: "cluster-\(key.layer.rawValue)-\(Int(cellsPerWorld))-\(key.x)-\(key.y)",
                layer: key.layer,
                center: Coordinate(latitude: lats.reduce(0, +) / n, longitude: lons.reduce(0, +) / n),
                count: members.count,
                bounds: BoundingBox(south: lats.min()!, west: lons.min()!, north: lats.max()!, east: lons.max()!))))
        }
        return items.sorted { $0.id < $1.id }
    }

    private struct CellKey: Hashable {
        let layer: SpotLayer
        let x: Int
        let y: Int
    }

    /// Web Mercator in 0...1 on both axes. Latitude is clamped to the Mercator limit.
    static func mercator(_ c: Coordinate) -> (x: Double, y: Double) {
        let lat = min(max(c.latitude, -85.05112878), 85.05112878) * .pi / 180
        let x = (c.longitude + 180) / 360
        let y = (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2
        return (x, y)
    }
}
