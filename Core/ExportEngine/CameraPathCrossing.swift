import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **How the camera crosses a leg with no road** — the contained arc
/// (`Docs/camera-arcs.md` §3), and the beat it plays in.
///
/// The move is one primitive: open out to an **apex** containing both ends,
/// translate while wide, close back in. What makes it safe is not the shape but
/// the way the two halves are interpolated — see `containedLerp`, which is where
/// the continuity guarantee actually lives.
///
/// **What is deliberately not here.** The camera never learns what a plane is
/// (`Docs/camera-arcs.md` §6). Everything below takes distances along the route
/// and camera frames; which sprite rides the arc is the timeline's business and
/// reaches the renderer through `SubjectState`.
extension CameraPath {
    /// One stretch of route with no road under it, in along-route metres.
    ///
    /// Metres rather than vertex indices because that is the axis the film's
    /// clock is warped against, and it is the axis both the beat and the body
    /// span have to be corrected on.
    struct Crossing: Equatable {
        let fromM: Double
        let toM: Double

        var distanceM: Double { max(toM - fromM, 0) }
    }

    /// A built crossing move: when it plays, and the three framings it visits.
    struct Arc {
        let startS: Double
        let endS: Double
        /// The body camera's own frame at `startS` — read from the simulated
        /// track, never re-derived, so the arc leaves and rejoins the dolly at
        /// exactly the value it already had.
        let source: CameraFrame
        let apex: CameraFrame
        let destination: CameraFrame
        /// When the move stops opening out and starts closing in.
        ///
        /// **The midpoint for every body crossing** — that is the accepted beat
        /// and it is unchanged. It is a stored value rather than an assumption
        /// because the *opening* arc of a type-2 film needs it somewhere else: at
        /// the instant the aircraft lands.
        ///
        /// **Why that matters, measured 2026-09-02.** With the split at the
        /// midpoint the camera was still closing while the sprite was still
        /// crossing, and `CameraPath.confine` — which keeps the subject inside the
        /// safe zone and is applied to every beat — dragged the centre 24 km in
        /// one snapshot step against `containedLerp`'s 7 km containment bound.
        /// 31 continuity violations, and the cause was not the zoom: it was a
        /// shrinking frame chasing a moving subject. Close *after* the subject has
        /// arrived and it is stationary, so `confine` does nothing and the move is
        /// a pure zoom, which stays contained by construction.
        let holdUntilS: Double

        init(
            startS: Double, endS: Double,
            source: CameraFrame, apex: CameraFrame, destination: CameraFrame,
            holdUntilS: Double? = nil
        ) {
            self.startS = startS
            self.endS = endS
            self.source = source
            self.apex = apex
            self.destination = destination
            self.holdUntilS = holdUntilS ?? (startS + endS) / 2
        }

        func contains(_ time: Double) -> Bool { time >= startS && time <= endS }

        /// The framing at `time`: out to the apex, then back in. Both halves are
        /// smoothstepped, so the move decelerates into the apex — the moment both
        /// places are on screen together — and accelerates out of it.
        ///
        /// When `source` and `apex` are the same frame the first half is an exact
        /// identity, which is how a type-2 film's still flight beat is expressed
        /// without a second primitive: the camera provably does not move, rather
        /// than nearly not moving.
        func frame(atTime time: Double) -> CameraFrame {
            if time <= holdUntilS {
                let out = max(holdUntilS - startS, 1e-6)
                return CameraPath.containedLerp(
                    source, apex, CameraPath.smoothstepPublic(min(max((time - startS) / out, 0), 1))
                )
            }
            let back = max(endS - holdUntilS, 1e-6)
            return CameraPath.containedLerp(
                apex, destination,
                CameraPath.smoothstepPublic(min(max((time - holdUntilS) / back, 0), 1))
            )
        }
    }

    /// **Interpolation that cannot show ground the neighbouring sample did not.**
    ///
    /// `lerp` moves the span geometrically and the centre **linearly in time**,
    /// which is right for the opening — a zoom in place, where the centre barely
    /// moves — and wrong for a crossing. Measured on the arithmetic: opening a
    /// 20 km body frame out to a 400 km apex, the centre has to travel ~190 km
    /// while the first frames widen by only ~30 km, so the early frames slide off
    /// ground the previous frame was showing. That is the strobe the continuity
    /// gate exists to catch, arriving through the front door.
    ///
    /// The fix is to make the centre a function of the **span** rather than of
    /// time: move a fixed fraction of the way across for each fixed fraction of
    /// the widening. Then the containment condition at every sample reduces to
    /// one global inequality —
    ///
    ///     |centre(to) − centre(from)| ≤ (to.spanM − from.spanM) / 2
    ///
    /// — which is *exactly* the statement "the looser frame contains the tighter
    /// one's footprint", i.e. the definition `apexFrame` builds to. So the arc is
    /// continuous by construction rather than by a threshold, on both axes, at
    /// any zoom ratio and any duration. Nothing needs tuning and nothing needs
    /// forgiving (`Docs/camera-arcs.md` §8).
    ///
    /// The span step stays geometric, so the *apparent* rate of zoom is constant,
    /// for the reason `lerp` already gives.
    ///
    /// Equal spans fall back to `lerp`. A pure translation cannot preserve
    /// containment — two equal frames at different centres, neither inside the
    /// other — so this is a degenerate arc rather than a case to support;
    /// `buildArcs` refuses to build one.
    static func containedLerp(_ from: CameraFrame, _ to: CameraFrame, _ fraction: Double) -> CameraFrame {
        guard from.spanM > 0, to.spanM > 0, from.spanM != to.spanM else {
            return lerp(from, to, fraction)
        }
        let span = from.spanM * pow(to.spanM / from.spanM, fraction)
        let progress = (span - from.spanM) / (to.spanM - from.spanM)
        return CameraFrame(
            centerLat: from.centerLat + (to.centerLat - from.centerLat) * progress,
            centerLon: from.centerLon + (to.centerLon - from.centerLon) * progress,
            spanM: span,
            bearing: 0
        )
    }

    /// The smallest frame containing **both end footprints**, padded.
    ///
    /// Footprints, not centres: containing the two centres would leave half of
    /// each end frame outside the apex, which breaks the inequality
    /// `containedLerp` depends on and would make the arc's first frames drop
    /// ground.
    ///
    /// `crossing_apex_padding` then does two jobs at once — it is what keeps the
    /// subject inside `camera_safe_zone_fraction` at the widest point (the
    /// subject sits at `1 / padding` of the half-frame), and it is the slack that
    /// keeps `CameraPath.confine` from firing and dragging the frame off the arc.
    static func apexFrame(
        source: CameraFrame, destination: CameraFrame, config: TrackingConfig.Export
    ) -> CameraFrame {
        containingFrame([source, destination], padding: config.crossingApexPadding, config: config)
    }

    /// **The smallest frame whose footprint contains every one of `frames`**,
    /// padded — the geometry `apexFrame` was, generalised to N frames because a
    /// second consumer needs exactly it.
    ///
    /// That consumer is `RecapSnapshotStations`: a station is one snapshot that
    /// serves a run of frames by reprojection, and it is correct precisely when
    /// it contains all of them (`Docs/camera-arcs.md` §7). Written as two
    /// separate footprint unions the two would drift, and the failure would be a
    /// frame that drops ground at one edge — invisible in a still, a flicker in
    /// motion.
    ///
    /// Footprints, not centres: containing the two centres would leave half of
    /// each end frame outside, which breaks the inequality `containedLerp`
    /// depends on.
    ///
    /// Flat-earth about the first frame's centre, which is why every caller
    /// pads. Over a station spanning hundreds of kilometres the difference
    /// between this and the provider's mercator is a fraction of a percent of
    /// the span — small, real, and absorbed by the padding rather than ignored.
    static func containingFrame(
        _ frames: [CameraFrame], padding: Double, config: TrackingConfig.Export
    ) -> CameraFrame {
        guard let origin = frames.first else {
            return CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
        }
        let referenceLat = frames.reduce(0.0) { $0 + $1.centerLat } / Double(frames.count)
        let metresPerDegreeLat = 111_320.0
        let metresPerDegreeLon = 111_320.0 * cos(referenceLat * .pi / 180)
        // Vertical ground covered by a frame is `spanM · height/width`; the
        // horizontal span needed to cover a north-south extent is therefore that
        // extent times width/height. Same convention as `fittingSpanM`.
        let aspect = Double(config.frameWidthPx) / Double(config.frameHeightPx)

        /// One frame's ground rectangle, in metres about `origin`'s centre.
        struct Footprint {
            let minEast: Double, maxEast: Double, minNorth: Double, maxNorth: Double

            init(_ frame: CameraFrame, origin: CameraFrame, perLon: Double, perLat: Double, aspect: Double) {
                let east = (frame.centerLon - origin.centerLon) * perLon
                let north = (frame.centerLat - origin.centerLat) * perLat
                minEast = east - frame.spanM / 2
                maxEast = east + frame.spanM / 2
                minNorth = north - frame.spanM / aspect / 2
                maxNorth = north + frame.spanM / aspect / 2
            }
        }
        let ends = frames.map {
            Footprint($0, origin: origin, perLon: metresPerDegreeLon, perLat: metresPerDegreeLat, aspect: aspect)
        }
        let minEast = ends.map(\.minEast).min() ?? 0
        let maxEast = ends.map(\.maxEast).max() ?? 0
        let minNorth = ends.map(\.minNorth).min() ?? 0
        let maxNorth = ends.map(\.maxNorth).max() ?? 0

        let contained = max(maxEast - minEast, (maxNorth - minNorth) * aspect)
        // Never tighter than the frames it has to contain: a crossing whose two
        // ends already share one body frame has nothing to open out of.
        let spanM = max(contained * padding, frames.map(\.spanM).max() ?? 0)
        return CameraFrame(
            centerLat: origin.centerLat + (minNorth + maxNorth) / 2 / metresPerDegreeLat,
            centerLon: origin.centerLon + (minEast + maxEast) / 2 / metresPerDegreeLon,
            spanM: spanM,
            bearing: 0
        )
    }

    /// Turns the `.crossing` entries of a built timeline into camera moves.
    ///
    /// An arc is built only when the apex is a genuinely different picture from
    /// the body frame — the same `opening_collapse_zoom_ratio` question the
    /// opening's beats already answer. A ferry between two piers inside one body
    /// frame keeps its beat (the sprite still crosses it, and it still leaves the
    /// body span alone) but gets no zoom, because there is nothing to open out
    /// to and a 6-second 1.1× move is a wobble, not a move.
    /// The film-time windows of the `.crossing` entries, in playback order —
    /// derived once at build time so neither the sprite nor the arc has to walk
    /// the timeline per frame.
    static func crossingBeats(in timeline: [TimelineEntry]) -> [ClosedRange<Double>] {
        timeline.compactMap { entry in
            guard case .crossing = entry.phase, entry.endS > entry.startS else { return nil }
            return entry.startS...entry.endS
        }
    }

    /// Everything the camera needs to know about this film's crossings, built in
    /// one step because both halves come from the same timeline and the arc's
    /// ends come from the same track.
    struct Moves {
        let arcs: [Arc]
        let beatsS: [ClosedRange<Double>]
    }

    static func crossingMoves(
        timeline: [TimelineEntry], track: [CameraFrame], fps: Int, config: TrackingConfig.Export,
        openingFrame: CameraFrame? = nil, openingEndsS: Double = 0
    ) -> Moves {
        Moves(
            arcs: buildArcs(
                timeline: timeline, track: track, fps: fps, config: config,
                openingFrame: openingFrame, openingEndsS: openingEndsS
            ),
            beatsS: crossingBeats(in: timeline)
        )
    }

    /// - Parameter openingFrame: the still frame a type-2 film opens on. The
    ///   crossing that starts as the opening ends takes it as **both** its source
    ///   and its apex, which is what makes that beat a still camera: the first
    ///   half interpolates a frame to itself, and only the second half moves.
    static func buildArcs(
        timeline: [TimelineEntry], track: [CameraFrame], fps: Int, config: TrackingConfig.Export,
        openingFrame: CameraFrame? = nil, openingEndsS: Double = 0
    ) -> [Arc] {
        /// The crossing the film opens on: the first one, and only when nothing
        /// but stop holds separates it from the title card.
        func isTheOpeningCrossing(_ entry: TimelineEntry, openingEndsS: Double) -> Bool {
            guard let firstCrossing = timeline.first(where: {
                if case .crossing = $0.phase { return true }
                return false
            }) else { return false }
            return entry.startS == firstCrossing.startS && entry.startS >= openingEndsS
        }

        guard !track.isEmpty else { return [] }
        func frame(at time: Double) -> CameraFrame {
            let index = Int((max(time, 0) * Double(fps)).rounded())
            return track[min(max(index, 0), track.count - 1)]
        }
        return timeline.compactMap { entry in
            guard case .crossing = entry.phase, entry.endS > entry.startS else { return nil }
            let destination = frame(at: entry.endS)

            // **Case C** (`Docs/camera-arcs.md` §4): the film opened *at* the
            // apex, so this arc has nowhere to open out to — it holds there while
            // the aircraft crosses, then closes into the destination. One move,
            // not two.
            //
            // Both `source` and `apex` are the opening's frame on purpose. Equal
            // endpoints make `containedLerp` an exact identity over the first
            // half, so the beat is *provably* still rather than nearly still —
            // which is what lets the continuity gate assert it instead of
            // forgiving it. The collapse guard below is skipped for the same
            // reason: it exists to drop an arc that would barely move, and this
            // one is deliberately motionless for half its length.
            // **Back to the opening's end, not to the crossing's own start.** The
            // departure airport is a stop, so its hold sits between the title card
            // and the flight — and if the arc began after it, the frame would jump
            // from the flight frame to a ~13 km body frame on the terminal and
            // back out again (measured: 71 violations from 4.33 s). Held instead,
            // the airport's photographs play over the frame the aircraft is about
            // to cross, which is the beat Chiu described.
            if let openingFrame, isTheOpeningCrossing(entry, openingEndsS: openingEndsS) {
                // The close begins when the aircraft lands and takes
                // `zoom_transition_s` — the same knob the opening's own closing
                // zoom uses, because this *is* that zoom: it is what carries the
                // film from its establishing frame into the body camera.
                let closeEndS = entry.endS + config.zoomTransitionS
                return Arc(
                    startS: min(entry.startS, openingEndsS), endS: closeEndS,
                    source: openingFrame, apex: openingFrame,
                    destination: frame(at: closeEndS), holdUntilS: entry.endS
                )
            }

            let source = frame(at: entry.startS)
            let apex = apexFrame(source: source, destination: destination, config: config)
            let widest = max(source.spanM, destination.spanM)
            guard widest > 0, apex.spanM > widest * config.openingCollapseZoomRatio else { return nil }
            return Arc(
                startS: entry.startS, endS: entry.endS,
                source: source, apex: apex, destination: destination
            )
        }
    }

    /// The along-route stretches with no road under them, from the leg ranges the
    /// timeline holds.
    ///
    /// A leg occupies a contiguous window of the concatenated route, so its
    /// distance range is simply its first and last vertices' cumulative
    /// distances. Ranges shorter than two vertices carry no distance and are
    /// dropped — a crossing with nothing to cross is not a beat.
    static func crossings(
        vertexRanges: [Range<Int>], cumulativeM: [Double]
    ) -> [Crossing] {
        vertexRanges.compactMap { range in
            guard range.lowerBound >= 0, range.upperBound <= cumulativeM.count,
                  range.count >= 2 else { return nil }
            let crossing = Crossing(
                fromM: cumulativeM[range.lowerBound], toM: cumulativeM[range.upperBound - 1]
            )
            return crossing.distanceM > 0 ? crossing : nil
        }
    }

    /// When each crossing arc plays, in film time.
    ///
    /// Exposed because the render loop has to **fine-sample** these stretches:
    /// the coarse keyframe interval cross-fades between two geometrically
    /// different pictures, which is the ghosting mechanism `HANDOFF.md`
    /// 2026-08-30 finding 1 describes, and an arc is the one place in the body
    /// where the pictures differ most. A temporary cost — camera-arc Pass 1's
    /// crop-scaling replaces it with a reprojection (`Docs/camera-arcs.md` §7).
    public var arcWindowsS: [ClosedRange<Double>] {
        arcs.map { $0.startS...$0.endS }
    }

    /// The crossing **beats** — the stretches with no road under them, in film
    /// time. Exposed so the continuity gate can assert that a type-2 film's
    /// camera is still for the whole of one, rather than for a duration it
    /// assumed.
    public var crossingBeatWindowsS: [ClosedRange<Double>] { crossingBeatsS }

    /// Whether `time` falls inside a crossing **beat** — the stretch with no road
    /// under it, which the film narrates with its own subject.
    ///
    /// Wider than `arcWindowsS`: a crossing whose two ends already share one body
    /// frame gets its beat and its sprite without earning a zoom (`buildArcs`),
    /// and the sprite is the honest half — it is what makes "every discontinuity
    /// is narrated" true (`Docs/camera-arcs.md` §8).
    public func isCrossing(atTime time: Double) -> Bool {
        crossingBeatsS.contains { $0.contains(min(max(time, 0), durationS)) }
    }

    /// How many seconds the crossings may take out of the travel budget.
    ///
    /// Each asks for `crossing_beat_s`, and the sum is capped the same way the
    /// stop holds are: one scale factor over all of them, so their relative
    /// weight survives, and travel never reaches zero. The cap is
    /// `max_hold_fraction` of the travel budget — the film already has exactly
    /// one rule for "time not spent covering ground", and a second constant for
    /// the same idea is a tunable nobody could reason about.
    static func crossingBeatS(
        count: Int, travelS: Double, config: TrackingConfig.Export
    ) -> Double {
        guard count > 0, travelS > 0 else { return 0 }
        let asked = config.crossingBeatS
        let cap = travelS * config.maxHoldFraction / Double(count)
        return max(min(asked, cap), 0)
    }
}
