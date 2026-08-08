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
    /// When the trail and the vehicle start moving. Earlier than `openingS`: the
    /// opening's closing zoom plays over an already-moving journey, which is what
    /// removed the frozen opening (Chiu 2026-08-01).
    public let journeyStartS: Double

    /// One leg's window into the flat route array, kept alongside the story it
    /// tells about itself. The camera works on the concatenated polyline (one
    /// speed-warped distance axis for the whole trip); the *reveal* is cut back
    /// apart along these ranges so each leg can be stroked for what it is.
    private struct LegRange {
        let range: Range<Int>
        let mode: TransportMode
        let provenance: RouteProvenance
    }

    let path: CameraPath
    let stops: [RecapTrip.Stop]
    let holds: [CameraPath.Hold]
    private let routeCoordinates: [RecapCoordinate]
    private let legRanges: [LegRange]
    let deck: RecapDeck
    let subjectParkS: Double
    /// When the subject first appears. Zero when there is no prologue.
    ///
    /// **Two sequences, chosen by what the trip opens on** (Chiu 2026-07-31):
    ///
    ///   opening → [first stop's pin/title/photos] → car appears → first leg
    ///   opening → car appears → first leg
    ///
    /// The first applies when the journey *starts at* a photo-bearing stop. The
    /// car must never appear only to park a moment later at the origin — that
    /// reads as a false start, and it is a sequencing fault, not a duration one:
    /// no dwell tuning can fix a car that should not have been on screen yet.
    let subjectArrivalStartS: Double
    let subjectArrivalEndS: Double
    private let titleCardS: Double
    private let endCardS: Double
    private let title: String
    private let subtitle: String
    private let statsLines: [String]
    private let callToAction: String
    private let shareURL: String?

    /// Fails on the same degenerate input as `CameraPath` (no usable route).
    ///
    /// **`establishing` and `pacing` are two different facts** (Chiu 2026-08-08).
    ///
    /// `establishing` is the installed map region's extent: a **rendering** fact,
    /// true only of the vector-tile substrate, and used for exactly two things —
    /// what the opening establishing shot frames, and the span cap that stops the
    /// camera framing ground the tiles cannot draw.
    ///
    /// `pacing` is a **story** fact: how long the film runs and how its time is
    /// shared between stops, which follows from how many stops there are and how
    /// many photographs each carries. It must never depend on which tiles happen
    /// to be installed.
    ///
    /// Until now a nil `establishing` meant *both* "no tiles" and "give me a short
    /// fixed-length film with no prologue", because the deterministic harnesses
    /// used nil to ask for the latter. That coupling made every trip outside an
    /// installed region come out 30 s long with no opening, for reasons that had
    /// nothing to do with its content. Harnesses now say `.fixed` and mean it.
    public init?(
        trip: RecapTrip,
        config: TrackingConfig.Export,
        establishing: RecapBounds? = nil,
        pacing: RecapPacing = .contentDerived
    ) {
        let route = trip.route
        let routePoints = route.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stopPoints = trip.stops.map { CameraPath.Point(lat: $0.coordinate.lat, lon: $0.coordinate.lon) }
        // `RecapDurationPlan` sizes each stop from its own photo count and fits
        // the whole film into the target window; `.fixed` skips it for a known
        // length. Either way this reads the trip, never the map.
        //
        // A stop's hold has to cover the whole scene, not just the photos: the car
        // parks on the way in and pulls away on the way out, and those beats are
        // *added* around the deck rather than taken out of it — otherwise every
        // stop would silently lose `2 · subject_park_s` of photo time.
        let (plan, stopHolds) = Self.pacing(for: trip, config: config, pacing: pacing)

        guard let path = CameraPath(
            route: routePoints, stops: stopPoints, config: config,
            stopHoldsS: stopHolds,
            totalDurationS: plan?.totalS ?? pacing.fixedTotalS,
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
        openingS = path.openingS
        journeyStartS = path.journeyStartS
        stops = trip.stops
        holds = path.holds
        routeCoordinates = route
        var offset = 0
        legRanges = trip.legs.map { leg in
            let range = offset..<(offset + leg.coordinates.count)
            offset = range.upperBound
            return LegRange(range: range, mode: leg.mode, provenance: leg.provenance)
        }
        deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        subjectParkS = config.subjectParkS
        // The car does not exist until the journey does. Through the country and
        // regional beats there is no vehicle on screen — it would be a sprite the
        // size of a mountain range, and narratively the trip has not begun. It
        // fades in across the last zoom, so by the time the route is framed the
        // car is there, ready to move.
        let arrival = Self.subjectArrival(
            plan: plan, openingS: path.openingS, holds: path.holds, stops: trip.stops, config: config
        )
        subjectArrivalStartS = arrival.startS
        subjectArrivalEndS = arrival.endS
        titleCardS = min(config.titleCardS, path.durationS)
        endCardS = config.endCardS
        title = trip.title
        subtitle = trip.subtitle
        statsLines = trip.statsLines
        callToAction = trip.callToAction
        shareURL = trip.shareURL
    }

    /// When the subject first appears, and the two sequences that decide it
    /// (Chiu 2026-07-31) — see `subjectArrivalStartS`.
    private static func subjectArrival(
        plan: RecapDurationPlan?, openingS: Double, holds: [CameraPath.Hold],
        stops: [RecapTrip.Stop], config: TrackingConfig.Export
    ) -> (startS: Double, endS: Double) {
        guard plan != nil, openingS > 0 else { return (0, 0) }

        // Does the journey open *on* a stop worth presenting? That is a stop
        // whose hold begins the moment the prologue ends (so it sits at the
        // trip's origin) and which actually has photos to show.
        let opensOnStop = holds.first.flatMap { hold -> CameraPath.Hold? in
            guard hold.startS <= openingS + 0.01,
                  stops.indices.contains(hold.stopIndex),
                  !stops[hold.stopIndex].photos.isEmpty
            else { return nil }
            return hold
        }
        guard let opensOnStop else {
            // Sequence B: nothing to present, so the car arrives with the route
            // and starts driving. Anchored to the prologue's **real** end, not to
            // the configured beat times — the opening collapses beats that do not
            // move the camera, so those two numbers are not the same.
            return (max(openingS - config.zoomTransitionS, 0), openingS)
        }
        // Sequence A: the stop tells itself first, with no vehicle on screen at
        // all, and the car arrives as that scene closes — the same pull-away ramp
        // every other stop ends on.
        let park = min(config.subjectParkS, (opensOnStop.endS - opensOnStop.startS) * 0.25)
        return (max(opensOnStop.endS - park, openingS), opensOnStop.endS)
    }

    /// How long the film runs and how its time is shared out.
    ///
    /// A **story** decision, so it reads only the trip and the config — never the
    /// map. `.contentDerived` sizes the film from its own content
    /// (`RecapDurationPlan`); `.fixed` is the deterministic harness path, which
    /// wants a known length and no prologue so a golden frame means something.
    ///
    /// Either way the returned holds already carry the park beats, which are
    /// *added* around each deck rather than taken out of it.
    private static func pacing(
        for trip: RecapTrip, config: TrackingConfig.Export, pacing: RecapPacing
    ) -> (plan: RecapDurationPlan?, holds: [Double]) {
        let deckPacing = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS
        )
        switch pacing {
        case .fixed:
            // No plan means `CameraPath` runs at its own `totalDurationS` with
            // `openingS` 0 — no prologue, so `zoom_transition_s` never enters the
            // opening and the subject-arrival ramp collapses to (0, 0). The stops
            // keep the dwells the trip itself carries.
            return (nil, trip.stops.map { $0.dwellS + 2 * config.subjectParkS })
        case .contentDerived:
            let plan = RecapDurationPlan.plan(
                photoCounts: trip.stops.map(\.photos.count), config: config, deck: deckPacing
            )
            let holds = trip.stops.indices.map { index in
                (index < plan.stopDwellS.count ? plan.stopDwellS[index] : trip.stops[index].dwellS)
                    + 2 * config.subjectParkS
            }
            return (plan, holds)
        }
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
    func parkRamp(_ hold: CameraPath.Hold) -> Double {
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
        // A stop the allocator gave no photographs to still happened, and the film
        // should say where it was (Chiu 2026-08-05): the pin lands with its name
        // and the journey moves on. It gets no deck and — via `activeScene` —
        // no park beat, so the car drives through rather than stopping.
        if activeScene(atTime: time) == nil, let quiet = quietStop(atTime: time) {
            contents.append(.stopLabel(
                name: quiet.stop.name, coordinate: quiet.stop.coordinate, detail: quiet.stop.detail,
                opacity: quietLabelOpacity(atTime: time, hold: quiet.hold)
            ))
        }
        if let active = activeScene(atTime: time) {
            let stop = active.stop
            let window = deckWindow(active.hold)
            let labelOpacity = leadLabelOpacity(atTime: time, hold: active.hold, deck: window)
            if labelOpacity > 0.001 {
                contents.append(.stopLabel(
                    name: stop.name, coordinate: stop.coordinate, detail: stop.detail, opacity: labelOpacity
                ))
            }
            if time >= window.start {
                // Only as many as the window can hold at `photoMinHoldS` each.
                let shown = affordablePhotoCount(deck: window, requested: stop.photos.count)
                contents.append(.photoDeck(RecapPhotoDeck(
                    photos: Array(stop.photos.prefix(shown)),
                    focusIndex: focusIndex(atTime: time, deck: window, count: shown),
                    reveal: deckReveal(atTime: time, deck: window),
                    opacity: deckOpacity(atTime: time, deck: window),
                    name: stop.name,
                    detail: stop.detail,
                    coordinate: stop.coordinate
                )))
            }
        }
        // Last, so it sits on top of everything it overlaps — and only across the
        // body: the title and end cards are full-bleed and own their seconds.
        if time >= titleCardS, time < durationS - endCardS {
            contents.append(.hud(
                dayLabel: dayLabel(atTime: time),
                place: holdingStop(atTime: time)?.name,
                travelledM: path.traveledDistanceM(atTime: time)
            ))
        }
        return contents
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

    static func smoothstep(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
