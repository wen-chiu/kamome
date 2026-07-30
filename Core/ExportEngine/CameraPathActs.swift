import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// How the camera decides what to hold in frame (Chiu 2026-07-25).
///
/// Split out of `CameraPath` to keep both files readable; the behaviour is
/// documented on `Act` below.
extension CameraPath {
    /// Time budget: holds first (their sum capped at `max_hold_fraction`), the
    /// rest is travel, split across legs in proportion to leg distance. Each
    /// anchor's hold is its per-stop `stopHoldsS` value (photo-deck length) or
    /// the uniform `stop_hold_s` fallback; the cap scales every hold by one
    /// factor so photo-heavy stops keep their relative weight.
    static func buildTimeline(
        anchors: [(stopIndex: Int, distanceM: Double)],
        totalM: Double,
        config: TrackingConfig.Export,
        stopHoldsS: [Double]?,
        startS: Double = 0,
        targetS: Double
    ) -> [TimelineEntry] {
        var holds = anchors.map { anchor -> Double in
            if let stopHoldsS, anchor.stopIndex < stopHoldsS.count {
                return max(0, stopHoldsS[anchor.stopIndex])
            }
            return config.stopHoldS
        }
        let totalHold = holds.reduce(0, +)
        let cap = max(targetS - startS, 0) * config.maxHoldFraction
        if totalHold > cap, totalHold > 0 {
            let factor = cap / totalHold
            holds = holds.map { $0 * factor }
        }
        let travelS = max(targetS - startS - holds.reduce(0, +), 0)

        var timeline: [TimelineEntry] = []
        var clock = startS
        if startS > 0 {
            // The prologue: the vehicle waits at the route's start, so the trail
            // has not begun and the camera has the frame to itself.
            timeline.append(.init(startS: 0, endS: startS, phase: .travel(fromM: 0, toM: 0)))
        }
        var legStartM = 0.0
        for (index, anchor) in anchors.enumerated() {
            let holdS = holds[index]
            let legM = max(0, anchor.distanceM - legStartM)
            let legS = travelS * legM / totalM
            timeline.append(
                .init(startS: clock, endS: clock + legS, phase: .travel(fromM: legStartM, toM: anchor.distanceM))
            )
            clock += legS
            timeline.append(
                .init(startS: clock, endS: clock + holdS, phase: .hold(stopIndex: anchor.stopIndex, atM: anchor.distanceM))
            )
            clock += holdS
            legStartM = anchor.distanceM
        }
        timeline.append(.init(startS: clock, endS: targetS, phase: .travel(fromM: legStartM, toM: totalM)))
        return timeline
    }

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

// MARK: - Framing geometry (pure, deterministic)

// Internal, not private: CameraPathActs.swift frames each act with these.
extension CameraPath {
    struct Bounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double
    }

    static func bounds(of route: [Point]) -> Bounds {
        var minLat = route[0].lat, maxLat = route[0].lat
        var minLon = route[0].lon, maxLon = route[0].lon
        for point in route {
            minLat = min(minLat, point.lat); maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon); maxLon = max(maxLon, point.lon)
        }
        return Bounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }

    /// Horizontal span that fits the whole route into the (portrait) frame:
    /// wide enough for the east-west extent, and for the north-south extent
    /// once scaled by the frame's aspect (vertical span = spanM · h/w).
    static func fittingSpanM(bounds: Bounds, config: TrackingConfig.Export) -> Double {
        let midLat = (bounds.minLat + bounds.maxLat) / 2
        let lonExtentM = Geo.distanceM(latA: midLat, lonA: bounds.minLon, latB: midLat, lonB: bounds.maxLon)
        let latExtentM = Geo.distanceM(latA: bounds.minLat, lonA: bounds.minLon, latB: bounds.maxLat, lonB: bounds.minLon)
        let aspect = Double(config.frameWidthPx) / Double(config.frameHeightPx)
        return max(lonExtentM, latExtentM * aspect)
    }

    /// Planar bearing (deg, 0 = north, clockwise) — `atan2(east, north)` with a
    /// cos(lat) correction. Enough for a follow-cam at recap zoom; degenerate
    /// (coincident) points face north.
    static func bearingDeg(from start: Point, to end: Point) -> Double {
        let meanLatRad = (start.lat + end.lat) / 2 * .pi / 180
        let east = (end.lon - start.lon) * cos(meanLatRad)
        let north = end.lat - start.lat
        guard east != 0 || north != 0 else { return 0 }
        let deg = atan2(east, north) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// Interpolate along the shortest arc from `start` to `end` (degrees), so a
    /// heading near 360° eases toward 0° the short way, not backwards.
    static func angleLerp(from start: Double, to end: Double, fraction: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let result = (start + delta * fraction).truncatingRemainder(dividingBy: 360)
        return result < 0 ? result + 360 : result
    }
}
