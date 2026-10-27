import KamomePersistence
import KamomeRouteMatching
import KamomeTripComposer

/// **The line a leg follows**: the road routing matched it to, when one is
/// stored (`segment.matched_polyline`), else its own points. One choice for the
/// film (`RecapComposer.legs`), the kilometres (`LegLength`) and Trip Detail's
/// map (`TripDetailModel.thinned`), so no screen draws one line and measures or
/// names another (#195: the map drew the points of a leg the diary called
/// 「已對齊道路」).
enum LegGeometry {
    struct Line: Equatable {
        let points: [Simplifier.Point]
        /// True when `points` is the matched road. Every stored road has at
        /// least two points (the providers refuse fewer), so this is true
        /// exactly when `RecapComposer.provenance` says `.reconstructed`.
        let isRoad: Bool
    }

    /// A stored road that decodes to fewer than two points is no road: the leg
    /// keeps its points, as the film always has.
    static func line(segment: SegmentRecord, points: [TrackpointRecord]) -> Line {
        if let encoded = segment.matchedPolyline, case let decoded = EncodedPolyline.decode(encoded), decoded.count >= 2 {
            return Line(points: decoded.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, isRoad: true)
        }
        return Line(points: points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, isRoad: false)
    }
}
