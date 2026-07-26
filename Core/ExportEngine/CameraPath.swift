import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// §4.5 step 1: the deterministic camera path for the recap video.
///
/// The **vehicle** travels the full-trip polyline speed-warped so the video
/// always lasts `export.target_duration_s` regardless of trip length. At each
/// stop it holds for `export.stop_hold_s` (the photo card moment); travel legs
/// between stops get smoothstep easing, so it decelerates into every hold and
/// accelerates out of it. Holds pin to the route point nearest the stop, not
/// the dwell center, so the vehicle never jumps off the polyline. When holds
/// would eat more than `export.max_hold_fraction` of the video, they shrink
/// proportionally — travel time never reaches zero.
///
/// The **camera** (`cameraFrame`) is a separate concern from the vehicle
/// (`position`), and since 2026-07-25 it **holds still**: one fixed frame per
/// act, re-framed only across a genuine jump (`CameraPathActs.swift`). It does
/// not follow the vehicle and does not zoom for stops. A static frame is what
/// makes the distance covered legible — the drawn line grows against a backdrop
/// the eye can measure — which is exactly what a continuously sliding, scaling
/// follow-cam destroyed. Camera and vehicle stay two outputs, not one: the
/// vehicle moves within a frame that does not.
///
/// Pure value math over Doubles: the same trip and config always produce the
/// same frames, which is what the golden-frame gate tests rely on.
public struct CameraPath {
    public struct Point: Equatable {
        public let lat: Double
        public let lon: Double

        public init(lat: Double, lon: Double) {
            self.lat = lat
            self.lon = lon
        }
    }

    /// The vehicle (the subject): where the marker is drawn and which way it
    /// faces. Projected through the snapshot by the compositor.
    public struct Position: Equatable {
        public let lat: Double
        public let lon: Double
        /// Direction of travel in degrees, 0 = north, clockwise. The route
        /// tangent while travelling; the approach heading while holding.
        public let heading: Double
        /// Index into the `stops` array passed at init while the vehicle is
        /// holding there, else nil. Drives the photo-card animation.
        public let holdingStopIndex: Int?
    }

    /// What the base-map snapshot is taken at (§4.5 step 2). `bearing` rotates
    /// the map heading-up; `spanM` is the horizontal ground span. Distinct from
    /// `Position`: in wide shots the camera frames the trip while the vehicle
    /// sits off-center in its real location.
    public struct CameraFrame: Equatable {
        public let centerLat: Double
        public let centerLon: Double
        public let spanM: Double
        public let bearing: Double
    }

    // Internal (not private) so the act-framing extension in CameraPathActs.swift
    // can read the speed-warped timeline it derives act windows from.
    enum Phase {
        case travel(fromM: Double, toM: Double)
        case hold(stopIndex: Int, atM: Double)
    }

    struct TimelineEntry {
        let startS: Double
        let endS: Double
        let phase: Phase
    }

    public struct Hold: Equatable {
        public let stopIndex: Int
        public let startS: Double
        public let endS: Double
    }

    public let frameCount: Int
    public let durationS: Double

    /// Hold windows in video time, in playback order — what `LinearTimeline`
    /// anchors each stop scene (pin/label lead → photo deck) to (decisions.md
    /// 2026-07-17: overlay moments are timeline events, not per-frame reads of
    /// the camera's hold state).
    public var holds: [Hold] {
        timeline.compactMap { entry in
            guard case let .hold(stopIndex, _) = entry.phase else { return nil }
            return Hold(stopIndex: stopIndex, startS: entry.startS, endS: entry.endS)
        }
    }

    private let fps: Int
    private let route: [Point]
    private let cumulativeM: [Double]
    private let timeline: [TimelineEntry]

    // Camera framing (cameraFrame). The map is held **still**: one fixed frame
    // per act, re-framed only where the journey genuinely jumps (Chiu
    // 2026-07-25). See `Act`.
    private let acts: [Act]
    private let zoomTransitionS: Double
    private let followHeadingUp: Bool

    /// Fails on degenerate input (fewer than two points or zero length) —
    /// the phantom-trip guard keeps such trips out of the DB, so a caller
    /// asking anyway has a bug upstream.
    ///
    /// `stopHoldsS` gives each stop (indexed like `stops`) its own hold
    /// duration — the photo deck makes a stop's dwell scale with its photo
    /// count (§5, `RecapDeck.dwellS`). nil keeps every stop at the uniform
    /// `export.stop_hold_s` (route-only / no-photo path, and the golden-frame
    /// tests). Either way the total holds are still capped at
    /// `export.max_hold_fraction` of the video so travel time never vanishes.
    public init?(
        route: [Point],
        stops: [Point],
        config: TrackingConfig.Export,
        stopHoldsS: [Double]? = nil
    ) {
        guard route.count >= 2 else { return nil }
        var cumulative = [0.0]
        cumulative.reserveCapacity(route.count)
        for index in 1..<route.count {
            let step = Geo.distanceM(
                latA: route[index - 1].lat, lonA: route[index - 1].lon,
                latB: route[index].lat, lonB: route[index].lon
            )
            cumulative.append(cumulative[index - 1] + step)
        }
        guard let totalM = cumulative.last, totalM > 0 else { return nil }

        let anchors = Self.stopAnchors(route: route, cumulativeM: cumulative, stops: stops)

        self.route = route
        self.cumulativeM = cumulative
        timeline = Self.buildTimeline(anchors: anchors, totalM: totalM, config: config, stopHoldsS: stopHoldsS)
        self.fps = config.fps
        durationS = config.targetDurationS
        frameCount = Int((config.targetDurationS * Double(config.fps)).rounded())

        zoomTransitionS = config.zoomTransitionS
        followHeadingUp = config.followHeadingUp
        acts = Self.buildActs(
            route: route, cumulativeM: cumulative, timeline: timeline,
            totalM: totalM, config: config
        )
    }

    /// Anchor each stop to its nearest route vertex, ordered along the path.
    private static func stopAnchors(
        route: [Point],
        cumulativeM: [Double],
        stops: [Point]
    ) -> [(stopIndex: Int, distanceM: Double)] {
        stops.enumerated().map { index, stop in
            var bestVertex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (vertex, point) in route.enumerated() {
                let distance = Geo.distanceM(latA: stop.lat, lonA: stop.lon, latB: point.lat, lonB: point.lon)
                if distance < bestDistance {
                    bestDistance = distance
                    bestVertex = vertex
                }
            }
            return (index, cumulativeM[bestVertex])
        }
        .sorted { $0.distanceM < $1.distanceM }
    }

    /// Time budget: holds first (their sum capped at `max_hold_fraction`), the
    /// rest is travel, split across legs in proportion to leg distance. Each
    /// anchor's hold is its per-stop `stopHoldsS` value (photo-deck length) or
    /// the uniform `stop_hold_s` fallback; the cap scales every hold by one
    /// factor so photo-heavy stops keep their relative weight.
    private static func buildTimeline(
        anchors: [(stopIndex: Int, distanceM: Double)],
        totalM: Double,
        config: TrackingConfig.Export,
        stopHoldsS: [Double]?
    ) -> [TimelineEntry] {
        let targetS = config.targetDurationS
        var holds = anchors.map { anchor -> Double in
            if let stopHoldsS, anchor.stopIndex < stopHoldsS.count {
                return max(0, stopHoldsS[anchor.stopIndex])
            }
            return config.stopHoldS
        }
        let totalHold = holds.reduce(0, +)
        let cap = targetS * config.maxHoldFraction
        if totalHold > cap, totalHold > 0 {
            let factor = cap / totalHold
            holds = holds.map { $0 * factor }
        }
        let travelS = targetS - holds.reduce(0, +)

        var timeline: [TimelineEntry] = []
        var clock = 0.0
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

    public func position(atFrame frame: Int) -> Position {
        position(atTime: Double(frame) / Double(fps))
    }

    public func position(atTime time: Double) -> Position {
        let (distanceM, holdIndex) = state(atTime: time)
        let point = coordinate(atDistance: distanceM)
        return Position(
            lat: point.lat, lon: point.lon,
            heading: heading(atDistance: distanceM),
            holdingStopIndex: holdIndex
        )
    }

    /// The base-map framing at `time`: the current act's **fixed** frame, eased
    /// into the next one across an act boundary.
    ///
    /// The map does not move with the vehicle and does not zoom for stops. A
    /// still frame is what makes the distance covered legible — the drawn line
    /// grows against a constant backdrop the eye can measure — and it keeps raw
    /// GPS wobble at its true, negligible scale instead of magnifying it.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        guard let current = acts.last(where: { time >= $0.startS }) ?? acts.first else {
            return CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
        }
        let bearing = followHeadingUp ? position(atTime: time).heading : 0
        guard let next = acts.first(where: { $0.startS > current.startS }) else {
            return CameraFrame(
                centerLat: current.centerLat, centerLon: current.centerLon,
                spanM: current.spanM, bearing: bearing
            )
        }
        // Ease across the seam so a jump reads as a deliberate re-frame rather
        // than a cut. Small lat/lon lerps are safe (no antimeridian trips).
        let transition = max(zoomTransitionS, 1e-6)
        let blend = Self.smoothstep(min(max((time - (next.startS - transition)) / transition, 0), 1))
        return CameraFrame(
            centerLat: current.centerLat + (next.centerLat - current.centerLat) * blend,
            centerLon: current.centerLon + (next.centerLon - current.centerLon) * blend,
            spanM: current.spanM + (next.spanM - current.spanM) * blend,
            bearing: bearing
        )
    }

    /// Along-route distance covered at `time` — the frame renderer's traveled
    /// polyline ends here.
    public func traveledDistanceM(atTime time: Double) -> Double {
        state(atTime: time).distanceM
    }

    /// Where the trail reveal has reached at `time`: how many route vertices lie
    /// fully behind the subject, plus the interpolated head point it stops at.
    ///
    /// Exposed as an index rather than only as points (typed-leg pass
    /// 2026-07-26) so a caller holding the route's leg boundaries can split the
    /// reveal per leg. `CameraPath` stays the single owner of the speed-warp
    /// math; the timeline just asks it where the cut fell.
    public func revealCut(atTime time: Double) -> (vertexCount: Int, head: Point) {
        let distanceM = traveledDistanceM(atTime: time)
        var vertexCount = 0
        for vertexM in cumulativeM where vertexM < distanceM { vertexCount += 1 }
        return (vertexCount, coordinate(atDistance: distanceM))
    }

    /// Route vertices already passed at `time`, closed with the interpolated
    /// head point, ready for the traveled-polyline stroke (§4.5 step 2).
    public func routePrefix(atTime time: Double) -> [Point] {
        let cut = revealCut(atTime: time)
        return Array(route[0..<cut.vertexCount]) + [cut.head]
    }

    private func state(atTime time: Double) -> (distanceM: Double, holdIndex: Int?) {
        let clamped = min(max(time, 0), durationS)
        // The timeline is a handful of entries per stop — linear scan is fine.
        let entry = timeline.last(where: { $0.startS <= clamped }) ?? timeline[0]
        switch entry.phase {
        case let .hold(stopIndex, atM):
            return (atM, stopIndex)
        case let .travel(fromM, toM):
            let span = entry.endS - entry.startS
            let progress = span > 0 ? (clamped - entry.startS) / span : 1
            let eased = Self.smoothstep(min(max(progress, 0), 1))
            return (fromM + (toM - fromM) * eased, nil)
        }
    }

    private func coordinate(atDistance distanceM: Double) -> Point {
        var low = 0
        var high = cumulativeM.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= distanceM { low = mid } else { high = mid }
        }
        let spanM = cumulativeM[high] - cumulativeM[low]
        guard spanM > 0 else { return route[low] }
        let fraction = min(max((distanceM - cumulativeM[low]) / spanM, 0), 1)
        return Point(
            lat: route[low].lat + (route[high].lat - route[low].lat) * fraction,
            lon: route[low].lon + (route[high].lon - route[low].lon) * fraction
        )
    }

    /// Heading (deg) of the route segment bracketing `distanceM` — the vehicle
    /// faces the way it is travelling. Binary search mirrors `coordinate`.
    private func heading(atDistance distanceM: Double) -> Double {
        var low = 0
        var high = cumulativeM.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if cumulativeM[mid] <= distanceM { low = mid } else { high = mid }
        }
        return Self.bearingDeg(from: route[low], to: route[high])
    }

    /// Ease-in/out (§4.5): zero velocity at both ends of every travel leg.
    private static func smoothstep(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
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
