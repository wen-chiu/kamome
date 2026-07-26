import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// How the camera decides what to hold in frame (Chiu 2026-07-25).
///
/// Split out of `CameraPath` to keep both files readable; the behaviour is
/// documented on `Act` below.
extension CameraPath {
    /// A stretch of the journey the camera can hold in one fixed frame.
    ///
    /// The camera used to fly: wide establishing shot, then a close follow-cam
    /// riding the vehicle, plus a dolly into every stop. That made "how far did
    /// I actually go" illegible — the map slid and scaled continuously, so the
    /// eye had nothing to measure against — and it magnified raw GPS noise at
    /// close zoom. The prototype and TravelBoast both hold the map still and let
    /// the *line* do the work, which is what this restores.
    ///
    /// A new act starts only at a genuine discontinuity: consecutive route
    /// points more than `export.act_split_km` apart. That is what a flight, a
    /// ferry, or a drive resuming in another region looks like in the data — a
    /// leap no honest single frame can hold. Everything else, stops included,
    /// plays inside one held frame.
    struct Act {
        let startS: Double
        let endS: Double
        let centerLat: Double
        let centerLon: Double
        let spanM: Double
    }

    /// Splits the route at genuine jumps and frames each resulting act to its own
    /// extent. One continuous drive yields a single act — one fixed frame for the
    /// whole film, which is the common case and the point of the design.
    static func buildActs(
        route: [Point],
        cumulativeM: [Double],
        timeline: [TimelineEntry],
        totalM: Double,
        config: TrackingConfig.Export
    ) -> [Act] {
        let splitM = config.actSplitKm * 1000
        var startVertex = 0
        var spans: [(from: Int, to: Int)] = []
        for vertex in 1..<route.count where cumulativeM[vertex] - cumulativeM[vertex - 1] > splitM {
            spans.append((startVertex, vertex - 1))
            startVertex = vertex
        }
        spans.append((startVertex, route.count - 1))

        let durationS = config.targetDurationS
        return spans.map { span in
            let slice = Array(route[span.from...span.to])
            let bounds = Self.bounds(of: slice)
            // Floor at camera_span_m so a tiny act (a single city block) does not
            // zoom absurdly far in; pad so the line never touches the edge.
            let spanM = max(
                config.cameraSpanM,
                Self.fittingSpanM(bounds: bounds, config: config) * config.wideSpanPadding
            )
            return Act(
                startS: Self.time(atDistance: cumulativeM[span.from], timeline: timeline, durationS: durationS),
                endS: Self.time(atDistance: cumulativeM[span.to], timeline: timeline, durationS: durationS),
                centerLat: (bounds.minLat + bounds.maxLat) / 2,
                centerLon: (bounds.minLon + bounds.maxLon) / 2,
                spanM: spanM
            )
        }
    }

    /// When the vehicle reaches `distanceM` — the inverse of the speed-warped
    /// timeline, used to give each act its time window.
    static func time(
        atDistance distanceM: Double, timeline: [TimelineEntry], durationS: Double
    ) -> Double {
        for entry in timeline {
            guard case let .travel(fromM, toM) = entry.phase else { continue }
            if distanceM <= toM {
                guard toM > fromM else { return entry.startS }
                let fraction = min(max((distanceM - fromM) / (toM - fromM), 0), 1)
                return entry.startS + (entry.endS - entry.startS) * fraction
            }
        }
        return durationS
    }
}
