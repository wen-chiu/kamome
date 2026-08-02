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
/// (`position`). Since 2026-08-01 it is a **dead-zone dolly** (`FollowCamera`):
/// one span fixed for the whole trip, translation only, and it moves solely when
/// the journey's leading edge presses against the dead zone. It is never
/// *placed* — only ever moved from where it already was — because two
/// consecutive frames must always share meaningful geography.
///
/// That replaced a per-*act* camera which framed each stretch of route to its
/// own bounds. Framing then came from data shape while timing came from the
/// clock, with nothing reconciling them: on a real multi-day import the acts
/// collapsed onto the `camera_span_m` floor and the camera crossed 110 km
/// between them. Camera and vehicle stay two outputs, not one — the vehicle
/// moves within a frame that mostly does not.
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

        /// Bearing is resolved once, at the end of `cameraFrame`, so the beat
        /// logic above it never has to thread a rotation it does not care about.
        func withBearing(_ bearing: Double) -> CameraFrame {
            CameraFrame(centerLat: centerLat, centerLon: centerLon, spanM: spanM, bearing: bearing)
        }
    }

    // Internal (not private) so the time-budget extension in CameraPathActs.swift
    // can build and read the speed-warped timeline.
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

    /// The body camera, pre-simulated once per frame (Chiu 2026-08-01). A
    /// dead-zone dolly at a span fixed for the whole trip — see `FollowCamera`.
    /// Acts no longer frame anything; they only report where the journey leaps.
    private let track: [CameraFrame]
    /// The trip's one body span. Every frame of the body uses it.
    let bodySpanM: Double
    /// Kept whole so the discontinuity detector and the dead-zone camera read the
    /// same tunables the path was built with, rather than a copied subset that
    /// can drift out of step with it.
    private let cutConfig: TrackingConfig.Export
    private let zoomTransitionS: Double
    private let followHeadingUp: Bool
    /// The **wide** half of the opening — country, then region. The final
    /// "route" beat is not a stored frame any more: it is the live follow camera,
    /// blended into over `zoomTransitionS`, which is what makes the handoff exact
    /// rather than approximately equal (Chiu 2026-08-01).
    private let prologue: Prologue?
    /// When the wide beats end and the closing zoom into the body begins.
    ///
    /// The journey does **not** start here — it starts when the zoom finishes.
    /// An earlier pass started it here so the closing zoom would play over a
    /// moving car, but that made the first stop reveal itself mid-zoom, against
    /// the rule that the camera never zooms while the journey is being presented.
    /// The freeze it was working around is fixed at its source instead: the wide
    /// beats are capped at ~1 s each, so the opening is continuous motion.
    private let wideEndS: Double
    /// The closing reveal: eases out to frame the whole journey once the last
    /// stop is done, landing exactly as the end card arrives.
    private let endRevealStartS: Double?
    private let endRevealFrame: CameraFrame
    /// When the opening finishes handing the frame to the body camera.
    private let openingEndsS: Double

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
        openingS: Double = 0,
        /// Time reserved at the end for the closing chrome. The journey's last
        /// hold finishes before it, so the end card never lands on a stop.
        journeyEndsBeforeS: Double = 0
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
        let frames = Int((total * Double(config.fps)).rounded())

        // The prologue's real length is only known once its beats are built —
        // near-duplicate beats collapse, so a trip whose region and route frame
        // the same picture opens in far less than the configured sum. Lay out a
        // provisional timeline first, purely to size the body span against a
        // realistic travel budget.
        let provisional = Self.buildTimeline(
            anchors: anchors, totalM: totalM, config: config,
            stopHoldsS: stopHoldsS, startS: 0, targetS: total
        )
        // Capped to what the installed region can actually draw. A trip that
        // covers most of its region — the real Iceland ring road does — asks for
        // a padded frame wider than the tiles, and beyond them there is no water
        // layer, only the style's background, so the data boundary appears as a
        // grey band across the film. The country beat learned this on 2026-08-02;
        // the body span and the closing reveal had not (real-data Stage 0).
        let span = Self.cappedToRegion(
            RecapDurationPlan.bodySpanM(
                routeDistanceM: totalM,
                travelS: Self.travelSeconds(in: provisional),
                routeBounds: Self.bounds(of: route),
                config: config
            ),
            establishing: establishing, config: config
        )
        bodySpanM = span

        // The wide beats only. The old third beat — a *stored* frame of the
        // first act — is gone: the opening now zooms into the live follow camera,
        // so the two can never disagree at the seam.
        let builtPrologue = openingS > 0
            ? Self.buildWideOpening(route: route, establishing: establishing, config: config, bodySpanM: span)
            : nil
        let wideEnd = max(min(builtPrologue?.totalS ?? 0, total), 0)
        // **The closing zoom is skipped when it would not go anywhere** (Chiu
        // 2026-08-02). Once the body span is wide enough to bind on the route's
        // own extent, the body frame *is* the regional beat — same centre, same
        // span — and the transition degenerates into 2.5 s of a camera easing
        // from a picture to itself.
        //
        // Worse than idle: because the body camera centres on the journey's
        // start rather than on the journey, a tighter body frame made this beat
        // both a zoom and a ~150 km translate toward the first stop, which read
        // as a redundant pan between the opening and the first stop's scene.
        // Collapsing it cuts the opening straight into that scene.
        let closingZoomMoves = builtPrologue.map { wide in
            !Self.isEffectivelyTheSame(
                wide.finalFrame,
                Self.bodyFrame(route: route, spanM: span, config: config),
                config: config
            )
        } ?? false
        let opening = builtPrologue == nil
            ? 0
            : min(wideEnd + (closingZoomMoves ? config.zoomTransitionS : 0), total)
        wideEndS = wideEnd

        // The closing reveal is its own beat after the journey, never a zoom
        // during it: the body's span is fixed by product rule.
        let reveal = builtPrologue == nil ? 0 : config.endRevealS
        let journeyEnd = max(total - journeyEndsBeforeS - reveal, opening)
        let journeyTimeline = Self.buildTimeline(
            anchors: anchors, totalM: totalM, config: config,
            stopHoldsS: stopHoldsS, startS: opening, targetS: journeyEnd
        )
        timeline = journeyTimeline
        self.fps = config.fps
        cutConfig = config
        durationS = total
        frameCount = frames

        zoomTransitionS = config.zoomTransitionS
        followHeadingUp = config.followHeadingUp
        prologue = builtPrologue
        openingEndsS = opening

        // Simulate the body once. Through the opening the subject is pinned at
        // the route's start, so those frames come out static for free and the
        // track is already settled when the opening hands over to it.
        let sampled = (0..<frames).map { frame -> (point: Point, parked: Bool) in
            let time = Double(frame) / Double(config.fps)
            let entry = journeyTimeline.last(where: { $0.startS <= min(max(time, 0), total) })
                ?? journeyTimeline[0]
            let distanceM = Self.distance(atTime: time, timeline: journeyTimeline, durationS: total)
            let parked: Bool
            if case .hold = entry.phase { parked = true } else { parked = false }
            return (Self.coordinate(atDistance: distanceM, route: route, cumulativeM: cumulative), parked)
        }
        track = FollowCamera.track(
            subject: sampled.map(\.point), parked: sampled.map(\.parked),
            routeBounds: Self.bounds(of: route), spanM: span, config: config
        )
        endRevealStartS = reveal > 0 ? journeyEnd : nil
        // The closing frame opens out *past* the body, so the film lands on the
        // whole journey with room around it rather than merely stopping. With a
        // wide body span the two would otherwise be the same picture and the
        // reveal would have nothing to reveal (Chiu 2026-08-02).
        let revealFrame = Self.frame(
            for: Self.bounds(of: route), config: config, padding: config.endRevealPadding
        )
        endRevealFrame = CameraFrame(
            centerLat: revealFrame.centerLat, centerLon: revealFrame.centerLon,
            spanM: Self.cappedToRegion(revealFrame.spanM, establishing: establishing, config: config),
            bearing: 0
        )
    }

    /// How long the opening actually runs, after collapsing beats that do not
    /// move the camera. Exposed so the timeline reports its real pacing.
    ///
    /// Note this is *later* than the journey's start: the last stretch of the
    /// opening is a zoom played over an already-moving car (Chiu 2026-08-01).
    public var openingS: Double { openingEndsS }

    /// When the trail and the vehicle start moving: once the opening has fully
    /// resolved onto the body camera, never during its zoom.
    public var journeyStartS: Double { openingEndsS }

    /// Film times at which the camera is **allowed** to break spatial continuity
    /// — one per genuine route discontinuity (flight / ferry / data gap).
    ///
    /// Everywhere else the frame must stay continuous, and the continuity gate
    /// treats a jump away from these times as a bug rather than as editing. The
    /// dead-zone camera reads the same list to place its deliberate transitions,
    /// so "where may we cut" has exactly one answer in the codebase.
    public var permittedCutTimesS: [Double] {
        Self.discontinuities(route: route, cumulativeM: cumulativeM, config: cutConfig)
            .map { Self.time(atDistance: $0.distanceM, timeline: timeline, durationS: durationS) }
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

    /// The base-map framing at `time` — three beats, in film order.
    ///
    /// 1. **Opening (wide).** Country, then region: held framings the viewer
    ///    reads *where* from before anything moves.
    /// 2. **Opening (closing zoom) → body.** A geometric ease from the last wide
    ///    beat into the live follow camera. The target is `track[frame]`, not a
    ///    stored copy of it, so at `openingS` the two are the same value by
    ///    construction and the handoff cannot drift.
    /// 3. **Body.** The dead-zone dolly at a span fixed for the trip:
    ///    translation only, never a zoom, never a rotation, never a cut.
    /// 4. **End reveal.** After the journey, an eased pull-back to the whole
    ///    route — its own beat, which is why the body can stay fixed.
    ///
    /// Every interpolation goes through `lerp`, whose span step is *geometric*.
    /// There is deliberately only one interpolation system: the act seam used to
    /// carry a second, linear one, and on a 97× pull-back linear burns almost the
    /// whole apparent zoom in its first third and then crawls — which is what
    /// made the old ending feel wrong.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        let subject = position(atTime: time)
        let bearing = followHeadingUp ? subject.heading : 0
        let live = trackFrame(atTime: time)

        let composed: CameraFrame
        if let endRevealStartS, time >= endRevealStartS {
            let reveal = max(cutConfig.endRevealS, 1e-6)
            let blend = Self.smoothstep(min(max((time - endRevealStartS) / reveal, 0), 1))
            composed = Self.lerp(live, endRevealFrame, blend)
        } else if let prologue, time < openingEndsS {
            if time < wideEndS {
                composed = prologue.frame(atTime: time)
            } else {
                let transition = max(zoomTransitionS, 1e-6)
                let blend = Self.smoothstep(min(max((time - wideEndS) / transition, 0), 1))
                composed = Self.lerp(prologue.finalFrame, live, blend)
            }
        } else {
            composed = live
        }
        // **The safe-zone guarantee is a post-condition of the whole camera**, not
        // a property of the follow simulation alone (Chiu 2026-08-01). The end
        // reveal is why: it translates its centre linearly toward the route's
        // bounds while the span grows geometrically, so mid-blend the two are out
        // of step and the subject can be carried clean off the frame — measured at
        // 157% of the way to the edge on Iceland. Applying the clamp here covers
        // every beat by construction, including any added later.
        guard time >= openingEndsS else { return composed.withBearing(bearing) }
        return Self.confine(composed, around: subject, config: cutConfig).withBearing(bearing)
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

    /// Where the body camera settles: the route's own framing at `spanM`, which
    /// is what the follow simulation converges on once the world clamp has had
    /// its say. Computed here too so the opening can ask "would my closing zoom
    /// actually move?" before the track exists.
    private static func bodyFrame(
        route: [Point], spanM: Double, config: TrackingConfig.Export
    ) -> CameraFrame {
        let bounds = Self.bounds(of: route)
        let aspect = Double(config.frameHeightPx) / Double(config.frameWidthPx)
        let metresPerDegreeLat = 111_320.0
        let midLat = (bounds.minLat + bounds.maxLat) / 2
        let metresPerDegreeLon = 111_320.0 * cos(midLat * .pi / 180)
        // The same clamp `FollowCamera` applies: start on the route's first point,
        // held inside the route's own box.
        let halfLat = spanM * aspect / 2 / metresPerDegreeLat
        let halfLon = spanM / 2 / metresPerDegreeLon
        let lat = bounds.minLat + halfLat > bounds.maxLat - halfLat
            ? midLat
            : min(max(route[0].lat, bounds.minLat + halfLat), bounds.maxLat - halfLat)
        let lon = bounds.minLon + halfLon > bounds.maxLon - halfLon
            ? (bounds.minLon + bounds.maxLon) / 2
            : min(max(route[0].lon, bounds.minLon + halfLon), bounds.maxLon - halfLon)
        return CameraFrame(centerLat: lat, centerLon: lon, spanM: spanM, bearing: 0)
    }

    /// Pulls a frame the minimum distance that keeps `subject` inside the inner
    /// `camera_safe_zone_fraction`. A no-op whenever it already is.
    private static func confine(
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

    /// The simulated body frame covering `time`, clamped to the track.
    private func trackFrame(atTime time: Double) -> CameraFrame {
        guard !track.isEmpty else { return CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0) }
        let index = Int((min(max(time, 0), durationS) * Double(fps)).rounded())
        return track[min(max(index, 0), track.count - 1)]
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

    /// Along-route distance at `time`, without needing an instance — the camera
    /// track is simulated during `init`, before `self` is usable.
    static func distance(atTime time: Double, timeline: [TimelineEntry], durationS: Double) -> Double {
        let clamped = min(max(time, 0), durationS)
        let entry = timeline.last(where: { $0.startS <= clamped }) ?? timeline[0]
        switch entry.phase {
        case let .hold(_, atM):
            return atM
        case let .travel(fromM, toM):
            let span = entry.endS - entry.startS
            let progress = span > 0 ? (clamped - entry.startS) / span : 1
            return fromM + (toM - fromM) * smoothstep(min(max(progress, 0), 1))
        }
    }

    /// Film seconds spent travelling in `timeline` — the body span's denominator.
    static func travelSeconds(in timeline: [TimelineEntry]) -> Double {
        timeline.reduce(0.0) { total, entry in
            guard case let .travel(fromM, toM) = entry.phase, toM > fromM else { return total }
            return total + max(entry.endS - entry.startS, 0)
        }
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

    private func coordinate(atDistance distanceM: Double) -> Point {
        Self.coordinate(atDistance: distanceM, route: route, cumulativeM: cumulativeM)
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
