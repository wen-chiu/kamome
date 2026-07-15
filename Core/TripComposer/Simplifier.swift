import Foundation
import KamomeTrackingEngine

/// §4.4 Douglas-Peucker display simplification. Raw points stay in the DB;
/// this only thins what the map draws.
public enum Simplifier {
    public struct Point: Equatable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    public static func douglasPeucker(_ points: [Point], epsilonM: Double) -> [Point] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplify(points, from: 0, to: points.count - 1, epsilonM: epsilonM, keep: &keep)
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func simplify(
        _ points: [Point],
        from start: Int,
        to end: Int,
        epsilonM: Double,
        keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        var maxDistance = 0.0
        var maxIndex = start
        for index in (start + 1)..<end {
            let distance = perpendicularDistanceM(points[index], points[start], points[end])
            if distance > maxDistance {
                maxDistance = distance
                maxIndex = index
            }
        }
        guard maxDistance > epsilonM else { return }
        keep[maxIndex] = true
        simplify(points, from: start, to: maxIndex, epsilonM: epsilonM, keep: &keep)
        simplify(points, from: maxIndex, to: end, epsilonM: epsilonM, keep: &keep)
    }

    /// Distance from `point` to the segment start–end, in meters, on a local
    /// equirectangular projection around `start`.
    private static func perpendicularDistanceM(_ point: Point, _ start: Point, _ end: Point) -> Double {
        let mPerDegLat = 111_320.0
        let mPerDegLon = mPerDegLat * cos(start.lat * .pi / 180)
        let px = (point.lon - start.lon) * mPerDegLon
        let py = (point.lat - start.lat) * mPerDegLat
        let ex = (end.lon - start.lon) * mPerDegLon
        let ey = (end.lat - start.lat) * mPerDegLat
        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return (px * px + py * py).squareRoot() }
        let fraction = max(0, min(1, (px * ex + py * ey) / lengthSquared))
        let dx = px - fraction * ex
        let dy = py - fraction * ey
        return (dx * dx + dy * dy).squareRoot()
    }
}
