import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// The one story shape the Replay MVP ships: **linear** — establishing → travel
/// legs → stops → finale, in trip order (render-layers refactor 2026-07-24). A
/// concrete struct (no `SceneDirector` / `Scene` / `TimelineCompiler` ceremony —
/// there is exactly one story shape) that directly produces the four
/// style-independent state streams the renderers consume:
///
///   `cameraFrame(atTime:)` · `subjectState(atTime:)` · `mapState(atTime:)` · `overlayContents(atTime:)`
///
/// It reuses `CameraPath`'s speed-warp / hold / easing math for subject motion
/// and framing, and adds the stop choreography: at each stop the `photoDeck`
/// overlay opens on its own reveal envelope (grow `deckZoomS` → hold
/// `n·deckPhotoHoldS` → shrink `deckZoomS`).
///
/// The camera does **not** move for a stop (Chiu 2026-07-25). It holds the act's
/// fixed frame throughout; a stop is told by the label and the card, not by
/// flying the map. Overlays never touch the camera.
///
/// When a smart `SceneDirector` arrives (Phase 4, deterministic, spec §7), it
/// slots in above this; the state streams and renderers do not change.
public struct LinearTimeline {
    public let durationS: Double
    /// Total rendered frames (`durationS · fps`) — what the render loop and
    /// exporter iterate; taken straight from the reused `CameraPath`.
    public let frameCount: Int
    /// How much of the film is the opening establishing sequence — 0 when there
    /// is no prologue. Exposed so a render can report its own pacing.
    public let openingS: Double

    /// One leg's window into the flat route array, kept alongside the story it
    /// tells about itself. The camera works on the concatenated polyline (one
    /// speed-warped distance axis for the whole trip); the *reveal* is cut back
    /// apart along these ranges so each leg can be stroked for what it is.
    private struct LegRange {
        let range: Range<Int>
        let mode: TransportMode
        let provenance: RouteProvenance
    }

    private let path: CameraPath
    private let stops: [RecapTrip.Stop]
    private let holds: [CameraPath.Hold]
    private let routeCoordinates: [RecapCoordinate]
    private let legRanges: [LegRange]
    private let deck: RecapDeck
    private let subjectParkS: Double
    /// When the subject fades in during the opening: the final zoom toward the
    /// route. Zero when there is no prologue.
    private let subjectArrivalStartS: Double
    private let subjectArrivalEndS: Double
    private let titleCardS: Double
    private let endCardS: Double
    private let title: String
    private let subtitle: String
    private let statsLines: [String]
    private let callToAction: String
    private let shareURL: String?

    /// Fails on the same degenerate input as `CameraPath` (no usable route).
    ///
    /// `establishing` is the installed map region's extent — what the opening
    /// establishing shot frames (Chiu 2026-07-30). Passing nil keeps the film
    /// exactly as it was: no prologue, `export.target_duration_s`, so every
    /// golden-frame test renders unchanged.
    public init?(trip: RecapTrip, config: TrackingConfig.Export, establishing: RecapBounds? = nil) {
        let route = trip.route
        let routePoints = route.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stopPoints = trip.stops.map { CameraPath.Point(lat: $0.coordinate.lat, lon: $0.coordinate.lon) }
        // Duration follows content when an establishing extent is supplied — the
        // cinematic path. `RecapDurationPlan` sizes each stop from its own photo
        // count and fits the whole film into the target window.
        //
        // A stop's hold has to cover the whole scene, not just the photos: the car
        // parks on the way in and pulls away on the way out, and those beats are
        // *added* around the deck rather than taken out of it — otherwise every
        // stop would silently lose `2 · subject_park_s` of photo time.
        let (plan, stopHolds) = Self.pacing(for: trip, config: config, establishing: establishing)

        guard let path = CameraPath(
            route: routePoints, stops: stopPoints, config: config,
            stopHoldsS: stopHolds,
            totalDurationS: plan?.totalS,
            establishing: establishing,
            openingS: plan?.openingS ?? 0,
            // The finale gets the frame to itself: the journey lands before the
            // end card appears, so the closing panel never prints across a stop's
            // photo card. Without this the last hold ran to the final frame and
            // the two overlapped.
            journeyEndsBeforeS: plan.map { _ in config.endCardS } ?? 0
        ) else { return nil }

        self.path = path
        durationS = path.durationS
        frameCount = path.frameCount
        openingS = plan?.openingS ?? 0
        stops = trip.stops
        holds = path.holds
        routeCoordinates = route
        var offset = 0
        legRanges = trip.legs.map { leg in
            let range = offset..<(offset + leg.coordinates.count)
            offset = range.upperBound
            return LegRange(range: range, mode: leg.mode, provenance: leg.provenance)
        }
        deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        subjectParkS = config.subjectParkS
        // The car does not exist until the journey does. Through the country and
        // regional beats there is no vehicle on screen — it would be a sprite the
        // size of a mountain range, and narratively the trip has not begun. It
        // fades in across the last zoom, so by the time the route is framed the
        // car is there, ready to move.
        if let plan {
            let toRoute = config.openingCountryS + config.zoomTransitionS + config.openingRegionalS
            subjectArrivalStartS = toRoute
            subjectArrivalEndS = min(toRoute + config.zoomTransitionS, plan.openingS)
        } else {
            subjectArrivalStartS = 0
            subjectArrivalEndS = 0
        }
        titleCardS = min(config.titleCardS, path.durationS)
        endCardS = config.endCardS
        title = trip.title
        subtitle = trip.subtitle
        statsLines = trip.statsLines
        callToAction = trip.callToAction
        shareURL = trip.shareURL
    }

    /// The film's pacing: a content-derived plan when a map region is installed,
    /// otherwise the trip's own dwells at the old fixed duration. Either way the
    /// returned holds already carry the park beats, which are *added* around each
    /// deck rather than taken out of it.
    private static func pacing(
        for trip: RecapTrip, config: TrackingConfig.Export, establishing: RecapBounds?
    ) -> (plan: RecapDurationPlan?, holds: [Double]) {
        let deckPacing = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS
        )
        guard establishing != nil else {
            return (nil, trip.stops.map { $0.dwellS + 2 * config.subjectParkS })
        }
        let plan = RecapDurationPlan.plan(
            photoCounts: trip.stops.map(\.photos.count), config: config, deck: deckPacing
        )
        let holds = trip.stops.indices.map { index in
            (index < plan.stopDwellS.count ? plan.stopDwellS[index] : trip.stops[index].dwellS)
                + 2 * config.subjectParkS
        }
        return (plan, holds)
    }

    // MARK: - The four state streams

    /// Subject motion (the route tangent) — straight from the reused CameraPath —
    /// plus the stop's **park / pull-away** presence (Chiu 2026-07-26).
    ///
    /// The car arrives at the stop, parks, and is gone while the stop tells its
    /// own story; it returns as the next leg begins. Before this, the car sat
    /// parked on the map for the whole hold and the stop's pin had to be shoved
    /// aside to avoid printing text across it — which put the pin kilometres from
    /// the place it was marking. Removing the car during the stop is what lets the
    /// pin sit exactly where the journey actually paused.
    public func subjectState(atTime time: Double) -> SubjectState {
        let position = path.position(atTime: time)
        let presence = subjectPresence(atTime: time)
        return SubjectState(
            lat: position.lat, lon: position.lon, heading: position.heading,
            emphasis: presence, isVisible: presence > 0.001
        )
    }

    /// 1 while travelling, 0 while parked, smoothstepped across `subjectParkS` at
    /// each edge of a stop scene. Only scenes that actually *show* something park
    /// the car: a hold with nothing to reveal (the route-only path) would otherwise
    /// delete the car and leave an empty map, which reads as a glitch rather than
    /// as a stop.
    private func subjectPresence(atTime time: Double) -> Double {
        // The opening: absent, then fading in across the zoom toward the route.
        if subjectArrivalEndS > 0, time < subjectArrivalEndS {
            guard time > subjectArrivalStartS else { return 0 }
            return Self.smoothstep((time - subjectArrivalStartS) / (subjectArrivalEndS - subjectArrivalStartS))
        }
        guard let scene = activeScene(atTime: time) else { return 1 }
        let park = parkRamp(scene.hold)
        guard park > 0 else { return 0 }
        if time < scene.hold.startS + park {
            return 1 - Self.smoothstep((time - scene.hold.startS) / park)
        }
        if time > scene.hold.endS - park {
            return Self.smoothstep((time - (scene.hold.endS - park)) / park)
        }
        return 0
    }

    /// The park ramp, clamped so a hold squeezed by `max_hold_fraction` still has
    /// a middle where the car is actually away.
    private func parkRamp(_ hold: CameraPath.Hold) -> Double {
        min(subjectParkS, (hold.endS - hold.startS) * 0.25)
    }

    /// Map presentation. MVP: fully opaque throughout (fades are a later addition).
    public func mapState(atTime time: Double) -> MapState {
        MapState(opacity: 1)
    }

    /// Camera framing: straight through to `CameraPath`, which holds one fixed
    /// frame per act. Nothing here modulates it — not the stop, not the deck.
    public func cameraFrame(atTime time: Double) -> CameraFrame {
        let frame = path.cameraFrame(atTime: time)
        return CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, bearing: frame.bearing
        )
    }

    /// Everything drawn over the map at `time`: the revealed trail, the trip
    /// chrome, and — at a stop — the two beats. Beat 1: the pin lands with its
    /// name floating above the vehicle. Beat 2: the photo deck opens (focus
    /// advancing through the rotate phase, the card growing on `deckReveal`)
    /// while the lead-in label cross-fades out, its identity handed to the pin +
    /// name drawn under the card.
    public func overlayContents(atTime time: Double) -> [OverlayContent] {
        var contents: [OverlayContent] = [.routeReveal(revealedLegs(atTime: time))]
        if time < titleCardS {
            contents.append(.titleChrome(title: title, subtitle: subtitle))
        }
        if time >= durationS - endCardS {
            contents.append(.endChrome(stats: statsLines, callToAction: callToAction, shareURL: shareURL))
        }
        if let active = activeScene(atTime: time) {
            let stop = active.stop
            let window = deckWindow(active.hold)
            let labelOpacity = leadLabelOpacity(atTime: time, hold: active.hold, deck: window)
            if labelOpacity > 0.001 {
                contents.append(.stopLabel(
                    name: stop.name, coordinate: stop.coordinate, detail: stop.detail,
                    dayLabel: stop.dayLabel, travelledM: path.traveledDistanceM(atTime: time),
                    opacity: labelOpacity
                ))
            }
            if time >= window.start {
                contents.append(.photoDeck(RecapPhotoDeck(
                    photos: stop.photos,
                    focusIndex: focusIndex(atTime: time, deck: window, count: stop.photos.count),
                    reveal: deckReveal(atTime: time, deck: window),
                    opacity: deckOpacity(atTime: time, deck: window),
                    name: stop.name,
                    detail: stop.detail,
                    dayLabel: stop.dayLabel,
                    travelledM: path.traveledDistanceM(atTime: time),
                    coordinate: stop.coordinate
                )))
            }
        }
        return contents
    }

    // MARK: - Stop choreography (overlay + subject — the camera still holds still)

    /// The stop scene playing at `time`, if any. A hold only counts as a scene
    /// when its stop has something to reveal — the subject and the overlays both
    /// read this, so the car can never park for a stop that draws nothing.
    private func activeScene(atTime time: Double) -> (hold: CameraPath.Hold, stop: RecapTrip.Stop)? {
        for hold in holds where hold.startS <= time && time < hold.endS {
            guard stops.indices.contains(hold.stopIndex) else { continue }
            let stop = stops[hold.stopIndex]
            guard !stop.photos.isEmpty else { return nil }
            return (hold, stop)
        }
        return nil
    }

    /// The deck's sub-window inside a stop's hold. The scene runs
    /// **park → label → deck → pull away**, so the card opens after the car has
    /// finished parking plus `labelLeadS`, and — importantly — *closes before the
    /// car comes back*. Without that last reservation the card is still covering
    /// the spot while the vehicle fades in behind it, and the departure never
    /// reads on screen.
    private func deckWindow(_ hold: CameraPath.Hold) -> (start: Double, end: Double) {
        let park = parkRamp(hold)
        let end = max(hold.endS - park, hold.startS)
        return (min(hold.startS + park + deck.labelLeadS, end), end)
    }

    /// The zoom ramp used at both edges of a deck window, clamped to 40% of the
    /// window so it always fits even when a stop-dense trip squeezed the hold
    /// (`max_hold_fraction`).
    private func zoomRamp(_ window: (start: Double, end: Double)) -> Double {
        min(deck.zoomS, (window.end - window.start) * 0.4)
    }

    /// **Card** envelope (Chiu 2026-07-25): the photo keeps growing across the
    /// whole hold — not just the camera's dolly-in — so the stop plays as a slow
    /// cinematic reveal rather than a card that pops to full size and sits
    /// there. It scales back down over the closing ramp as the scene closes.
    private func deckReveal(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        let openEnd = window.end - zoom
        let opening = openEnd - window.start
        guard opening > 0 else { return 0 }
        if time <= openEnd {
            // The card blooms: it rises quickly, passes full size, and settles
            // back — an arrival rather than a grow. The overshoot decays across
            // the opening so the card is exactly at rest by the time it holds.
            let progress = (time - window.start) / opening
            let eased = Self.smoothstep(progress)
            let overshoot = sin(min(max(progress, 0), 1) * .pi) * Self.deckBloomOvershoot
            return eased + overshoot * (1 - eased)
        }
        guard zoom > 0 else { return 0 }
        return Self.smoothstep((window.end - time) / zoom)
    }

    /// Peak of the bloom past full size, as a fraction. Matches the renderer's
    /// `deckRevealOvershoot` ceiling; the style clamps to it.
    private static let deckBloomOvershoot = 0.06

    /// Card opacity: fades in over the opening ramp, out over the closing one.
    private func deckOpacity(atTime time: Double, deck window: (start: Double, end: Double)) -> Double {
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return time >= window.start ? 1 : 0 }
        if time < window.start + zoom { return Self.smoothstep((time - window.start) / zoom) }
        if time > window.end - zoom { return Self.smoothstep((window.end - time) / zoom) }
        return 1
    }

    /// The stop's pin and name. It **fades up exactly as the car parks**, so the
    /// stop's identity is handed from the vehicle to the pin at the same place
    /// rather than appearing somewhere else on the map; solid through the rest of
    /// beat 1; then handed on again to the card's own pin + name as the deck
    /// opens.
    private func leadLabelOpacity(
        atTime time: Double, hold: CameraPath.Hold, deck window: (start: Double, end: Double)
    ) -> Double {
        let park = parkRamp(hold)
        let arriving = park > 0 ? Self.smoothstep((time - hold.startS) / park) : 1
        guard time >= window.start else { return arriving }
        let zoom = zoomRamp(window)
        guard zoom > 0 else { return 0 }
        return min(arriving, 1 - Self.smoothstep((time - window.start) / zoom))
    }

    /// Which photo is in focus: the rotate phase (between the zoom edges) split
    /// into `count` equal slots. Grow holds photo 0 (highlight leads); shrink
    /// holds the last.
    private func focusIndex(atTime time: Double, deck window: (start: Double, end: Double), count: Int) -> Int {
        let zoom = zoomRamp(window)
        let rotateStart = window.start + zoom
        let rotateLength = max((window.end - zoom) - rotateStart, 1e-6)
        let slot = rotateLength / Double(count)
        return min(max(Int((time - rotateStart) / slot), 0), count - 1)
    }

    /// The revealed trail, cut back into legs (typed-leg pass 2026-07-26). The
    /// camera reveals along one continuous distance axis; this maps the cut back
    /// onto the leg ranges so a reconstructed motorway and an inferred straight
    /// line reach the renderer as separate strokes with separate stories.
    ///
    /// The leg the head is inside gets the interpolated head point appended, so
    /// the trail still ends exactly under the vehicle rather than at the last
    /// whole vertex.
    private func revealedLegs(atTime time: Double) -> [RecapRouteLeg] {
        let cut = path.revealCut(atTime: time)
        let head = RecapCoordinate(lat: cut.head.lat, lon: cut.head.lon)
        var revealed: [RecapRouteLeg] = []

        for leg in legRanges {
            guard cut.vertexCount > leg.range.lowerBound else { break }
            let end = min(cut.vertexCount, leg.range.upperBound)
            var coordinates = Array(routeCoordinates[leg.range.lowerBound..<end])
            if cut.vertexCount < leg.range.upperBound { coordinates.append(head) }
            guard coordinates.count >= 2 else { continue }
            revealed.append(RecapRouteLeg(
                coordinates: coordinates, mode: leg.mode, provenance: leg.provenance
            ))
        }
        return revealed
    }

    private static func smoothstep(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
