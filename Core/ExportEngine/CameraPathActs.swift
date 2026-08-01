import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// The film's **time budget**, and where the journey genuinely leaps.
///
/// This file used to also decide camera framing — one fixed frame per "act",
/// fitted to that act's own bounds. That is what the 2026-08-01 redesign
/// removed: framing derived from data shape is exactly how the camera came to
/// cut between unrelated views, so it now belongs to `FollowCamera`, which only
/// ever *moves* the frame it already has.
///
/// What survives here is the half that was never about the camera: how long each
/// stop holds and each leg travels, and which gaps in the route are real leaps
/// rather than fast driving.
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

    /// A genuine leap in the journey: two consecutive route vertices further
    /// apart than `export.act_split_km`. A flight, a ferry, or a drive resuming
    /// in another region — a gap no honest continuous camera move can cover.
    ///
    /// **This is the only place the camera may break continuity.** Everywhere
    /// else the frame must stay spatially continuous (camera continuity rule,
    /// Chiu 2026-08-01), and `RecapCameraContinuityTests` enforces exactly that:
    /// a jump anywhere but here fails the suite.
    struct Discontinuity: Equatable {
        /// The vertex the leap lands *on* — the first point of the new stretch.
        let vertexIndex: Int
        /// Along-route distance at the leap, for mapping onto the film clock.
        let distanceM: Double
        /// How far the leap is, so a transition can be sized to it.
        let leapM: Double
    }

    /// Every genuine leap in `route`, in travel order.
    ///
    /// All that remains of the acts system (2026-08-01), and deliberately so:
    /// detection is a fact about the *journey* — a ferry is a ferry — while
    /// framing was a decision about the *camera*, and conflating the two is what
    /// made acts visible to the audience.
    static func discontinuities(
        route: [Point], cumulativeM: [Double], config: TrackingConfig.Export
    ) -> [Discontinuity] {
        guard route.count > 1 else { return [] }
        let splitM = config.actSplitKm * 1000
        return (1..<route.count).compactMap { vertex in
            let leapM = cumulativeM[vertex] - cumulativeM[vertex - 1]
            guard leapM > splitM else { return nil }
            return Discontinuity(vertexIndex: vertex, distanceM: cumulativeM[vertex], leapM: leapM)
        }
    }

    /// When the vehicle reaches `distanceM` — the inverse of the speed-warped
    /// timeline. Used to place a discontinuity on the film clock.
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

// Internal, not private: the opening's wide beats and the body span are
// framed with these.
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
