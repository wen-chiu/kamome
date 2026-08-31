import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Nested types and pure statics moved out of `CameraPath` itself (Chiu
/// 2026-08-07, "option 1" of the lint split). None of this touches instance
/// state — every function here takes what it needs as arguments, which is
/// exactly what let it move without widening any stored property's access.
///
/// **Why this shape, not the construction/sampling split that was tried
/// first:** `private` is file-scoped in Swift, so an `extension CameraPath` in
/// another file cannot see the stored properties (`fps`, `followHeadingUp`,
/// `prologue`, `endRevealStartS`, `endRevealFrame`, `cutConfig`, …). Splitting
/// along "what builds the path" vs. "what samples it" would have forced ~10 of
/// them from `private` to `internal` just to satisfy the compiler — trading the
/// camera's encapsulation for a lint rule, on a file two continuity gates
/// depend on. Chiu rejected that. This split instead takes only what was
/// already free of `self`: two small value types used as the timeline's
/// currency, and the static math that computes over them.
extension CameraPath {
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

    // Internal (not private) so the time-budget extension in CameraPathActs.swift
    // can build and read the speed-warped timeline.
    enum Phase {
        case travel(fromM: Double, toM: Double)
        case hold(stopIndex: Int, atM: Double)
        /// A stretch with **no road under it**, played in its own fixed beat
        /// rather than at the film's travel rate (`Docs/camera-arcs.md` §3).
        ///
        /// Its own case rather than a flag on `.travel` because two things have
        /// to tell it apart, and both are load-bearing: `travelSeconds` must not
        /// count it (or the body span is sized against a flight), and the camera
        /// plays an arc over it instead of a dolly. The subject still moves
        /// across it exactly as it moves across travel, which is why every
        /// distance-from-time reader treats the two the same.
        case crossing(fromM: Double, toM: Double)
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

    /// Anchor each stop to its nearest route vertex, ordered along the path.
    static func stopAnchors(
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

    /// A span no wider than the installed region can cover. Without an extent
    /// there are no tiles to fall off, so the ask stands.
    static func cappedToRegion(
        _ spanM: Double, establishing: RecapBounds?, config: TrackingConfig.Export
    ) -> Double {
        guard let establishing else { return spanM }
        let bounds = Bounds(
            minLat: establishing.minLat, maxLat: establishing.maxLat,
            minLon: establishing.minLon, maxLon: establishing.maxLon
        )
        return min(spanM, max(containedSpanM(bounds: bounds, config: config), config.cameraSpanM))
    }

    /// Where the body camera is when the opening hands over to it.
    ///
    /// **Corrected 2026-08-08.** This used to be the route's own framing — the
    /// world clamp applied to the first point — and claimed to be "what the follow
    /// simulation converges on". It is not: the clamp is only the dolly's *starting*
    /// position, and the spring then runs throughout the opening (the vehicle waits
    /// at the route's start, so it is stationary, not parked) and walks the camera
    /// to the dead-zone boundary around it. On New Zealand the two differ by 25 km,
    /// which is how the opening came to hand over into a hard cut.
    ///
    /// The settled frame belongs to the camera that produces it, so it lives in
    /// `FollowCamera` now and this only names the moment.
    static func bodyFrame(
        route: [Point], spanM: Double, config: TrackingConfig.Export
    ) -> CameraFrame {
        FollowCamera.restingFrame(
            subject: route[0], routeBounds: Self.bounds(of: route), spanM: spanM, config: config
        )
    }

    /// Pulls a frame the minimum distance that keeps `subject` inside the inner
    /// `camera_safe_zone_fraction`. A no-op whenever it already is.
    static func confine(
        _ frame: CameraFrame, around subject: Position, config: TrackingConfig.Export
    ) -> CameraFrame {
        let aspect = Double(config.frameHeightPx) / Double(config.frameWidthPx)
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = 111_320.0 * cos(subject.lat * .pi / 180)
        let halfLonDeg = frame.spanM / 2 * config.cameraSafeZoneFraction / metresPerDegreeLon
        let halfLatDeg = frame.spanM * aspect / 2 * config.cameraSafeZoneFraction / metresPerDegreeLat
        return CameraFrame(
            centerLat: min(max(frame.centerLat, subject.lat - halfLatDeg), subject.lat + halfLatDeg),
            centerLon: min(max(frame.centerLon, subject.lon - halfLonDeg), subject.lon + halfLonDeg),
            spanM: frame.spanM,
            bearing: frame.bearing
        )
    }

    /// Along-route distance at `time`, without needing an instance — the camera
    /// track is simulated during `init`, before `self` is usable.
    static func distance(atTime time: Double, timeline: [TimelineEntry], durationS: Double) -> Double {
        let clamped = min(max(time, 0), durationS)
        let entry = timeline.last(where: { $0.startS <= clamped }) ?? timeline[0]
        switch entry.phase {
        case let .hold(_, atM):
            return atM
        case let .travel(fromM, toM), let .crossing(fromM, toM):
            let span = entry.endS - entry.startS
            let progress = span > 0 ? (clamped - entry.startS) / span : 1
            return fromM + (toM - fromM) * smoothstep(min(max(progress, 0), 1))
        }
    }

    /// Film seconds spent travelling in `timeline` — the body span's denominator.
    ///
    /// **Crossings are deliberately excluded** (`HANDOFF.md` 2026-08-21 finding
    /// 5). The body span is a *rate*: how much window the ground crosses per
    /// second while the dolly is following. A crossing is not followed by the
    /// dolly at all — it has its own arc — so counting its seconds here would
    /// buy the body a slower rate it never gets to spend.
    static func travelSeconds(in timeline: [TimelineEntry]) -> Double {
        timeline.reduce(0.0) { total, entry in
            guard case let .travel(fromM, toM) = entry.phase, toM > fromM else { return total }
            return total + max(entry.endS - entry.startS, 0)
        }
    }

    /// Along-route metres the **body camera** actually has to cross — the whole
    /// route less every crossing.
    ///
    /// The other half of the same correction. `RecapDurationPlan.bodySpanM`
    /// floors the span at `routeDistanceM / (travelS × pan rate)`, so on a
    /// cross-region trip the flight's hundreds of kilometres were what forced the
    /// destination to render as a smudge — symptom 2 of
    /// `Docs/cross-region-journeys.md` in exact code terms.
    ///
    /// **This is still one span per trip, not a span per segment.** With travel
    /// time shared in proportion to distance (`buildTimeline`), every local
    /// journey crosses ground at the same rate, so "derived from the largest
    /// local journey" and "derived from the union of the local journeys" are the
    /// same number — and this computes it without introducing the per-act framing
    /// rejected on 2026-08-02.
    static func localDistanceM(totalM: Double, crossings: [Crossing]) -> Double {
        max(totalM - crossings.reduce(0) { $0 + $1.distanceM }, 0)
    }

    static func coordinate(atDistance distanceM: Double, route: [Point], cumulativeM: [Double]) -> Point {
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

    /// Ease-in/out (§4.5): zero velocity at both ends of every travel leg.
    static func smoothstep(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// The body span, and everything needed to derive it: the opening the film
    /// establishes on, and the travel budget the pan floor is measured against.
    /// Grouped so `CameraPath.init` reads as one step rather than four.
    struct BodySpanRequest {
        let prologue: Prologue?
        let route: [Point]
        let anchors: [(stopIndex: Int, distanceM: Double)]
        let totalM: Double
        let crossings: [Crossing]
        let stopHoldsS: [Double]?
        let totalDurationS: Double
        let establishing: RecapBounds?
        let config: TrackingConfig.Export
    }

    static func bodySpan(_ request: BodySpanRequest) -> Double {
        let route = request.route, config = request.config, totalM = request.totalM
        // A provisional timeline just for the travel budget: the real one cannot
        // exist yet, because it starts where the opening ends.
        let provisional = buildTimeline(
            anchors: request.anchors, totalM: totalM, config: config,
            stopHoldsS: request.stopHoldsS, crossings: request.crossings,
            startS: 0, targetS: request.totalDurationS
        )
        return RecapDurationPlan.bodySpanM(
            establishedSpanM: establishedSpanM(
                prologue: request.prologue, route: route,
                establishing: request.establishing, config: config
            ),
            // The crossing's distance leaves the term and its seconds leave the
            // denominator together — half of either correction would be worse
            // than neither.
            routeDistanceM: localDistanceM(totalM: totalM, crossings: request.crossings),
            travelS: travelSeconds(in: provisional), config: config
        )
    }

    /// The span the opening establishes: the first beat the viewer sees at t=0,
    /// which is what the body span divides. Falls back to the regional framing for
    /// a film with no prologue at all, so `.fixed` pacing still gets a sane body.
    static func establishedSpanM(
        prologue: Prologue?, route: [Point], establishing: RecapBounds?, config: TrackingConfig.Export
    ) -> Double {
        if let first = prologue?.beats.first { return first.frame.spanM }
        return cappedToRegion(
            frame(for: bounds(of: route), config: config, padding: config.wideSpanPadding).spanM,
            establishing: establishing, config: config
        )
    }

    /// What `simulatedTrack` needs — grouped so the call reads as one value
    /// instead of eight positional arguments.
    struct TrackRequest {
        let route: [Point]
        let cumulativeM: [Double]
        let journeyTimeline: [TimelineEntry]
        let frameCount: Int
        let fps: Int
        let durationS: Double
        let spanM: Double
        let config: TrackingConfig.Export
    }

    /// Pre-simulates the body camera for every frame of the journey. Through
    /// the opening the subject is pinned at the route's start, so those frames
    /// come out static for free and the track is already settled when the
    /// opening hands over to it.
    static func simulatedTrack(_ request: TrackRequest) -> [CameraFrame] {
        let sampled = (0..<request.frameCount).map { frame -> (point: Point, parked: Bool) in
            let time = Double(frame) / Double(request.fps)
            let entry = request.journeyTimeline.last(where: { $0.startS <= min(max(time, 0), request.durationS) })
                ?? request.journeyTimeline[0]
            let distanceM = distance(atTime: time, timeline: request.journeyTimeline, durationS: request.durationS)
            let parked: Bool
            // A crossing is motion, not a hold: the dolly keeps following, so
            // that the frame the arc lands on is the body camera's own — which
            // is what makes the rejoin exact rather than approximately equal.
            if case .hold = entry.phase { parked = true } else { parked = false }
            return (coordinate(atDistance: distanceM, route: request.route, cumulativeM: request.cumulativeM), parked)
        }
        return FollowCamera.track(
            subject: sampled.map(\.point), parked: sampled.map(\.parked),
            routeBounds: bounds(of: request.route), spanM: request.spanM, config: request.config
        )
    }

    /// The closing reveal frame: opens out *past* the body so the film lands on
    /// the whole journey with room around it rather than merely stopping. With
    /// a wide body span the two would otherwise be the same picture and the
    /// reveal would have nothing to reveal (Chiu 2026-08-02).
    static func endRevealFrame(
        route: [Point], establishing: RecapBounds?, config: TrackingConfig.Export
    ) -> CameraFrame {
        let routeBounds = bounds(of: route)
        let revealFrame = frame(for: routeBounds, config: config, padding: config.endRevealPadding)
        let spanM = cappedToRegion(revealFrame.spanM, establishing: establishing, config: config)
        // **A reveal too tight to hold the journey must land where the journey
        // ended** — the same correction `wideBeat` got on 2026-08-08, arriving
        // here on 2026-08-30 because the first fixture elongated enough to
        // trigger it did not exist until then.
        //
        // `cappedToRegion` can shrink the reveal below the span the route needs,
        // because beyond the installed tiles there is nothing to draw. Centred on
        // the route's box anyway, the "reveal" then flies from the destination out
        // to a point neither end of the trip is near — 150 km of open sea on the
        // crossing fixture, across a 47 km frame, which broke the continuity gate
        // at 64.0 s with 38% of the ground surviving. It is the same fault
        // `wideBeat` describes: a beat that has lost its reason to exist and kept
        // its motion.
        //
        // **No shipped film changes.** `establishing` is permanently nil since
        // MapLibre was parked (2026-08-15), so `cappedToRegion` is a no-op and the
        // padded reveal contains the route by construction — the guard below never
        // fires. Measured on the crossing fixture: 0 continuity breaks either way
        // on that path.
        guard spanM < fittingSpanM(bounds: routeBounds, config: config) else {
            return CameraFrame(
                centerLat: revealFrame.centerLat, centerLon: revealFrame.centerLon,
                spanM: spanM, bearing: 0
            )
        }
        let landing = route[route.count - 1]
        return CameraFrame(centerLat: landing.lat, centerLon: landing.lon, spanM: spanM, bearing: 0)
    }
}
