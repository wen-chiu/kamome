import Foundation
import KamomeTrackingEngine

/// **Where on the route each stop's scene plays.** Split out of
/// `CameraPathCore` (file length) when it stopped being a one-line nearest
/// search (#349).
extension CameraPath {
    /// Anchor each stop to a route vertex, **in the order the stops happened**,
    /// ordered along the path.
    ///
    /// 🔴 **The nearest vertex, but never behind the stop before it** (#349,
    /// 2026-11-02). This was the nearest vertex anywhere on the route, which is
    /// right until the route passes a place twice. Then a later stop there —
    /// the hotel on the second night, the arrival airport on the way home, the
    /// near end of an out-and-back on the way back — took the first pass's
    /// vertex, and its scene played there. Measured on a one-hotel trip with a
    /// day trip each day: holds 0, 2, 4, 6, 1, 3, 5, every hotel night first.
    /// Rendered on a round trip: the HUD read Day 1 → Day 4 → Day 1 → Day 2.
    /// Which pass won came down to metres of photo-centroid jitter.
    ///
    /// `stops` arrive in the order they happened (`TripRepository.detail` reads
    /// them by `arrived_at`, and nothing on the way reorders them), and so does
    /// the route. So this chooses the vertices with the **least total distance
    /// that never go backwards**: one pass over the route per stop, carrying the
    /// best total of the stop before at or behind each vertex.
    ///
    /// **Identical wherever the old answer was already in order** — every trip
    /// that does not revisit a place. Each stop's earliest nearest vertex is
    /// then also the earliest optimum here, so those films do not move; only a
    /// revisit changes.
    ///
    /// The way back is kept as each stop's *records* — the vertices where its
    /// running best fell — rather than one pointer per vertex, so memory stays
    /// O(route + records) on a long trip. The distance work is the same
    /// stops × vertices the nearest search always did.
    static func stopAnchors(
        route: [Point],
        cumulativeM: [Double],
        stops: [Point]
    ) -> [(stopIndex: Int, distanceM: Double)] {
        guard !route.isEmpty else { return [] }
        // records[i]: ascending vertices where stop i's best total strictly
        // fell. Its earliest best at or behind vertex v is the last record ≤ v.
        var records: [[Int]] = []
        records.reserveCapacity(stops.count)
        // The best total of the stop before, at or behind each vertex.
        var behind = [Double](repeating: 0, count: route.count)
        var running = [Double](repeating: 0, count: route.count)
        for stop in stops {
            var best = Double.greatestFiniteMagnitude
            var falls: [Int] = []
            for (vertex, point) in route.enumerated() {
                let total = behind[vertex]
                    + Geo.distanceM(latA: stop.lat, lonA: stop.lon, latB: point.lat, lonB: point.lon)
                if total < best {
                    best = total
                    falls.append(vertex)
                }
                running[vertex] = best
            }
            records.append(falls)
            swap(&behind, &running)
        }

        var vertices = [Int](repeating: 0, count: stops.count)
        var limit = route.count - 1
        for index in stops.indices.reversed() {
            // A coordinate that is not a number never sets a record; the old
            // search left such a stop on vertex 0, and so does this.
            let vertex = records[index].last { $0 <= limit } ?? 0
            vertices[index] = vertex
            limit = vertex
        }
        return vertices.enumerated().map { (stopIndex: $0.offset, distanceM: cumulativeM[$0.element]) }
    }
}
