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
    /// The film's one sanctioned discontinuity — see `CameraPath.titleCutS`.
    /// Published so the continuity gate can scan *from* it.
    public let titleCutS: Double?
    /// When the trail and the vehicle start moving. Earlier than `openingS`: the
    /// opening's closing zoom plays over an already-moving journey, which is what
    /// removed the frozen opening (Chiu 2026-08-01).
    public let journeyStartS: Double

    /// One leg's window into the flat route array, kept alongside the story it
    /// tells about itself. The camera works on the concatenated polyline (one
    /// speed-warped distance axis for the whole trip); the *reveal* is cut back
    /// apart along these ranges so each leg can be stroked for what it is.
    /// Internal rather than private since 2026-09-02: `LinearTimelinePacing`
    /// builds these, and Swift scopes `private` to the file.
    struct LegRange {
        let range: Range<Int>
        let mode: TransportMode
        let provenance: RouteProvenance
        /// Whether routing established there is no road here — the one fact that
        /// earns a leg its own beat and a camera arc (`RecapTrip.Leg.isCrossing`).
        let isCrossing: Bool
    }

    let path: CameraPath
    let stops: [RecapTrip.Stop]
    let holds: [CameraPath.Hold]
    /// Internal, not private, since 2026-09-03: `LinearTimelineCrossing` owns
    /// the trail reveal, and Swift scopes `private` to the file. Same widening,
    /// same reason, as `LegRange` itself.
    let routeCoordinates: [RecapCoordinate]
    let legRanges: [LegRange]
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
    let endCardS: Double
    /// The boarding pass, resolved once at build time. nil on every film that is
    /// not a type-2 opening, and nil when `CountryExtent` cannot name both ends —
    /// see `journeyCard(trip:locale:)`.
    let journeyCard: RecapJourneyCard?
    /// The flight's two ends, for the marks drawn over the opening. **Kept apart
    /// from `journeyCard`**: a mark needs no country name, so an end the table
    /// cannot name still gets one (`flightEnds(atTime:)`).
    let flightEndCoordinates: (origin: RecapCoordinate, destination: RecapCoordinate)?
    /// How long the card takes to arrive and to leave, each. **`deck_zoom_s`
    /// deliberately reused**: it is the film's one "a card arrives" ramp, and a
    /// second tunable saying the same thing is a number nobody could reason about
    /// (`CLAUDE.md` rule 7's spirit — the tunable exists, so no new one is added).
    let cardFadeS: Double
    private let title: String
    private let subtitle: String
    private let statsLines: [String]
    private let callToAction: String
    private let shareURL: String?

    /// Which of the three films this is (`RecapFilmType`), and whether its
    /// opening is the still flight frame rather than a country card. Exposed so
    /// the continuity gate can report both and assert the second.
    public let filmType: RecapFilmType
    public let opensOnTheFlight: Bool

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
        trip untrimmedTrip: RecapTrip,
        config: TrackingConfig.Export,
        establishing: RecapBounds? = nil,
        pacing: RecapPacing = .contentDerived,
        /// The base map's declared ceiling
        /// (`MapRendererCapabilities.maxFramableLongitudeDeg`). Only the type-2
        /// opening reads it, and only to choose between its two forms.
        substrateMaxLongitudeDeg: Double? = nil,
        /// The viewer's language, for the **second** line of each region name on
        /// the Journey Card (TAIWAN / 台灣). The first line is always English —
        /// a boarding pass is an English artefact.
        ///
        /// ⚠️ Injectable because `Locale.current` makes a rendered frame
        /// device-dependent, exactly as `CountryExtent.localizedName` already is.
        /// Pin it in a desk harness or two machines render different films.
        locale: Locale = .current
    ) {
        // **A type-2 film is a film about the destination**, so the origin's drive
        // comes out before anything is measured (`RecapTypeTwoFilm`). Every other
        // film passes through untouched.
        let trip = untrimmedTrip.filmType.hasDestinationAbroad
            ? RecapTypeTwoFilm.trimmedToTheDestination(untrimmedTrip, config: config)
            : untrimmedTrip

        // Which of the type-2 opening's two forms this film takes — both are main
        // paths (`CrossingFraming`).
        // ⚠️ **Classified from the UNTRIMMED trip.** The trim leaves one local
        // journey, which `RecapFilmType` honestly reads as a local trip — so
        // asking the trimmed trip turns every type-2 film back into a type-1 one.
        // Measured when it did: 71 gate violations.
        let flightFrame = CrossingFraming.openingFrame(
            trip: untrimmedTrip, config: config, substrateMaxLongitudeDeg: substrateMaxLongitudeDeg
        )

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

        // Where the legs with no road sit on the concatenated polyline — the
        // camera needs them before it can size the body span.
        let crossingRanges = Self.crossingVertexRanges(in: trip.legs)

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
            journeyEndsBeforeS: plan.map { _ in config.endCardS } ?? 0,
            crossingVertexRanges: crossingRanges,
            openingFlightFrame: flightFrame
        ) else { return nil }

        self.path = path
        durationS = path.durationS
        frameCount = path.frameCount
        openingS = path.openingS
        titleCutS = path.titleCutS
        journeyStartS = path.journeyStartS
        stops = trip.stops
        holds = path.holds
        routeCoordinates = route
        legRanges = Self.legWindows(of: trip.legs)
        deck = Self.deck(config: config)
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
        filmType = untrimmedTrip.filmType
        // Both halves of the camera's own condition, not just the frame. The
        // camera opens on the flight when it has a frame **and** an opening to
        // put it in; deriving this from the frame alone would let the two
        // disagree on any path with `openingS == 0` (fixed pacing, golden
        // frames) — a reporter contradicting the thing it reports on, which is
        // the shape of defect this project keeps finding one film at a time.
        opensOnTheFlight = flightFrame != nil && path.openingS > 0
        cardFadeS = config.deckZoomS
        // **Only a type-2 opening carries a pass.** Gated on the camera's own
        // condition rather than on "has a crossing": a body crossing in some later
        // film would otherwise get a boarding pass in the middle of a road trip,
        // and this round is type-2 only.
        flightEndCoordinates = opensOnTheFlight ? RecapTypeTwoFilm.crossingEnds(trip) : nil
        journeyCard = flightEndCoordinates == nil ? nil : Self.journeyCard(trip: trip, locale: locale)
    }

    /// When the subject first appears, and the two sequences that decide it
    /// (Chiu 2026-07-31) — see `subjectArrivalStartS`.
    public func subjectState(atTime time: Double) -> SubjectState {
        let position = path.position(atTime: time)
        let presence = subjectPresence(atTime: time)
        return SubjectState(
            lat: position.lat, lon: position.lon, heading: position.heading,
            emphasis: presence, isVisible: presence > 0.001,
            role: path.isCrossing(atTime: time) ? .crossing : .vehicle
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
        // Under the card and under everything else: the two ends are the ground
        // the opening is read against, not chrome over it.
        if let ends = flightEnds(atTime: time) { contents.insert(ends, at: 1) }
        if let card = journeyCardContent(atTime: time) {
            contents.append(.journeyCard(card))
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
                // **The local journey, never the flight** (Chiu 2026-09-02). The
                // trail reveal still uses the whole route — the dashed leg has to
                // be drawn while the sprite crosses it — so the two readers of
                // this axis deliberately ask different questions of it.
                travelledM: path.traveledLocalDistanceM(atTime: time)
            ))
        }
        return contents
    }

    static func smoothstep(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
