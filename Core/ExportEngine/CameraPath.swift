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
    /// The one-time opening establishing sequence. Everything after `prologue`
    /// is the static per-act camera, unchanged (Chiu 2026-07-30).
    private let prologue: Prologue?

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
        stopHoldsS: [Double]? = nil,
        /// The film's whole length. Defaults to `export.target_duration_s` so
        /// existing callers and golden-frame tests are unaffected; `LinearTimeline`
        /// passes a content-derived total (`RecapDurationPlan`).
        totalDurationS: Double? = nil,
        /// The map region's extent, for the country view. nil = no tiles, so the
        /// opening widens the trip's own bounds instead.
        establishing: RecapBounds? = nil,
        /// Length of the opening. Zero disables it entirely, which is what keeps
        /// every pre-existing test rendering exactly as before.
        openingS: Double = 0
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
        let total = totalDurationS ?? config.targetDurationS
        // The journey's clock starts after the prologue: the vehicle sits at the
        // route's start while the camera establishes the geography.
        let opening = max(min(openingS, total), 0)
        timeline = Self.buildTimeline(
            anchors: anchors, totalM: totalM, config: config,
            stopHoldsS: stopHoldsS, startS: opening, targetS: total
        )
        self.fps = config.fps
        durationS = total
        frameCount = Int((total * Double(config.fps)).rounded())

        zoomTransitionS = config.zoomTransitionS
        followHeadingUp = config.followHeadingUp
        acts = Self.buildActs(
            route: route, cumulativeM: cumulative, timeline: timeline,
            totalM: totalM, config: config
        )
        prologue = opening > 0
            ? Self.buildPrologue(
                route: route, establishing: establishing, config: config,
                routeFrame: acts.first.map {
                    CameraFrame(centerLat: $0.centerLat, centerLon: $0.centerLon, spanM: $0.spanM, bearing: 0)
                } ?? Self.frame(for: Self.bounds(of: route), config: config, padding: config.wideSpanPadding)
            )
            : nil
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
        // The opening owns the camera until the route is framed; after that the
        // act frames take over and never move again (Chiu 2026-07-30).
        if let prologue, time < prologue.totalS {
            return prologue.frame(atTime: time)
        }
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

    /// Same easing, reachable from the prologue extension so the opening moves
    /// feel like the act seams rather than like a separate title sequence.
    static func smoothstepPublic(_ progress: Double) -> Double { smoothstep(progress) }

    /// Ease-in/out (§4.5): zero velocity at both ends of every travel leg.
    private static func smoothstep(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
