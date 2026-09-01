import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// The one-time opening establishing sequence (Chiu 2026-07-30).
///
/// **Why the film needed it.** It used to open on the first route segment, so a
/// viewer met a glowing line before knowing what country they were looking at.
/// The prologue answers *where* before it shows *what*: the whole
/// country/island, then the trip's region, then the route — each eased into the
/// next, then held long enough to read.
///
/// **This is the only camera movement in the film.** Once the route is framed the
/// camera holds still, per act, north-up, exactly as before (Chiu 2026-07-25 —
/// a moving map hides the route's real shape and the distance covered). There is
/// deliberately no per-stop approach: a stop is told by the pin and the card, and
/// the two-beat presentation already gives it presence without flying the map.
extension CameraPath {
    /// One held framing in the opening.
    struct Beat {
        let frame: CameraFrame
        let holdS: Double
    }

    /// The opening as a sequence of held framings joined by eased transitions.
    ///
    /// **Beats that do not move are dropped** (Chiu 2026-07-31). A trip that fits
    /// in one act frames its region and its route identically, so the "regional →
    /// route" transition moved nothing and the two holds either side of it were a
    /// frozen picture — 6.4 s of a film in which literally nothing changed, right
    /// before the first stop. A list of beats with near-duplicates collapsed
    /// spends time only where the camera is actually going somewhere.
    struct Prologue {
        let beats: [Beat]
        let transitionS: Double

        /// When the wide beats are done — the moment the journey's clock starts
        /// and the closing zoom into the body camera begins.
        var totalS: Double {
            beats.reduce(0) { $0 + $1.holdS } + Double(max(beats.count - 1, 0)) * transitionS
        }

        /// The last wide framing — what the closing zoom eases *from*.
        var finalFrame: CameraFrame {
            beats.last?.frame ?? CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
        }

        /// When the title card's held frame cuts to the film proper, or nil when
        /// there is no card beat to cut out of.
        ///
        /// Exposed so the continuity gate can begin its scan **at** the cut. That
        /// is not an exemption: it is the statement that the establishing card is
        /// not part of the continuous camera, which is what makes the one
        /// sanctioned discontinuity checkable instead of forgiven.
        var cutTimeS: Double? {
            guard beats.count > 1, transitionS == 0 else { return nil }
            return beats[0].holdS
        }

        /// The framing at `time`. Holds, then eases, then holds — the same
        /// smoothstep the act seams use, so the opening feels like the rest of the
        /// film rather than a separate title sequence.
        func frame(atTime time: Double) -> CameraFrame {
            guard let first = beats.first else {
                return CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0)
            }
            var cursor = 0.0
            for (index, beat) in beats.enumerated() {
                if time <= cursor + beat.holdS { return beat.frame }
                cursor += beat.holdS
                guard index + 1 < beats.count else { return beat.frame }
                let next = beats[index + 1].frame
                if time < cursor + transitionS {
                    return CameraPath.lerp(beat.frame, next, CameraPath.smoothstepPublic((time - cursor) / transitionS))
                }
                cursor += transitionS
            }
            return beats.last?.frame ?? first.frame
        }
    }

    /// Builds the **wide** half of the opening: country, then region.
    ///
    /// `establishing` is the installed map region's own extent — the honest
    /// country/island unit, and never wider than the tiles we have. Without it
    /// (no vector tiles, so Apple's map renders) the country view falls back to
    /// the trip's own bounds widened by `country_view_padding`, which is the most
    /// an offline app can claim to know about the surrounding geography.
    ///
    /// **The third beat is gone** (Chiu 2026-08-01). It used to be a stored copy
    /// of the first act's frame, held for `opening_route_s` with the vehicle
    /// still pinned at distance zero — a picture in which, by construction,
    /// nothing on screen could move. `CameraPath` now zooms from the last wide
    /// beat straight into the live follow camera while the journey is already
    /// running, so the opening resolves *onto* motion instead of into a freeze.
    ///
    /// **Takes no body span** (2026-08-09). It used to accept one "so a wide beat
    /// that already frames the body tightly can collapse against it", but the
    /// parameter was never read. Removing it is what lets the opening be built
    /// *before* the body span, which is now derived from what this establishes.
    /// The wide beats, or nil when the film has no opening at all. Lifted out of
    /// the initializer purely for its length; the ordering comment above the call
    /// is the part that matters.
    static func wideOpening(
        openingS: Double, route: [Point], crossings: [Range<Int>],
        establishing: RecapBounds?, config: TrackingConfig.Export
    ) -> Prologue? {
        guard openingS > 0 else { return nil }
        return buildWideOpening(
            route: route,
            openingRoute: openingRoute(route: route, crossings: crossings),
            establishing: establishing, config: config
        )
    }

    static func buildWideOpening(
        route: [Point],
        openingRoute: [Point],
        establishing: RecapBounds?,
        config: TrackingConfig.Export
    ) -> Prologue {
        // **Beat 2 is one local journey, not the trip's union** (Chiu 2026-08-31,
        // proposal 2A). A frame fitted to the union spends its span on ground the
        // viewer never visits and leaves the place a smudge — 274 km of body span
        // against 18.6 km on `ishigaki-crossing`
        // (`Docs/handoff-crop-scaling.md` §4).
        //
        // *Which* local journey is `CameraPath.openingRoute`, and its doc is worth
        // reading before changing anything here: on a local trip it is the whole
        // trip, which is proposal 2A exactly; on a cross-region trip it is the one
        // the body camera actually starts in, which becomes the destination on its
        // own once the origin leaves the recap.
        let destination = openingRoute.count >= 2 ? openingRoute : route
        let destinationBounds = bounds(of: destination)
        let regionalAsked = frame(for: destinationBounds, config: config, padding: config.wideSpanPadding)
        let regional = wideBeat(
            spanM: regionalAsked.spanM,
            route: destination, tripBounds: destinationBounds, config: config
        )

        // **Beat 1 is the country, and it is a title card's backdrop.** The
        // country is what an ordinary viewer recognises — nobody knows where "New
        // South Wales" is. Framed to *contain* the country exactly (padding 1.0),
        // which is not a tunable: it is "the whole country and no more".
        //
        // `cappedToRegion` is deliberately NOT applied here any more. It fits a
        // beat *inside* an extent so the tiles' own edge never shows, and with
        // MapLibre parked there are no tiles to fall off — Apple Maps is global.
        // Left in place it turned a country beat into the largest portrait frame
        // that fits inside the trip's bounds: 46.6 km on `ishigaki-crossing`,
        // which is a city, not a country.
        let country = destination.first.flatMap { CountryExtent.containing(lat: $0.lat, lon: $0.lon) }
        let countryFrame: CameraFrame
        if let country {
            countryFrame = frame(for: Self.bounds(of: country.bounds), config: config, padding: 1.0)
        } else {
            // **A real answer, said out loud** (`Arch.md` §6). No row covers this
            // trip, so the film cannot claim to show a country and falls back to
            // exactly what every film did before: the trip's own bounds widened.
            // Adding a row to `CountryExtent.all` is what fixes it.
            KamomeLog.recap.notice("opening: no country extent covers this trip, establishing on trip bounds")
            countryFrame = frame(for: bounds(of: route), config: config, padding: config.countryViewPadding)
        }

        // A country beat barely wider than the destination beat is two pictures
        // the eye cannot tell apart, so the title simply rides the destination
        // frame and the film opens where it stays.
        let countryAddsContext = countryFrame.spanM > regional.spanM * config.openingCollapseZoomRatio
        let wanted = countryAddsContext
            ? [
                // **The beat's length IS the card's length.** Chiu's rule is that
                // the cut lands as the title leaves: a cut under the card reads as
                // a film convention, a cut a moment after it reads as a bug.
                // Written as `titleCardS` rather than checked against
                // `opening_country_s`, so the two cannot drift apart at all.
                Beat(frame: countryFrame, holdS: config.titleCardS),
                Beat(frame: regional, holdS: config.openingRegionalS)
            ]
            // The title always belongs to the first beat, whichever that is.
            : [Beat(frame: regional, holdS: config.titleCardS)]
        // `transitionS: 0` **is the cut** (Chiu 2026-08-31). Beat 1 is chrome —
        // the viewer reads a title card as a card, not as a camera — so a cut out
        // of it costs no continuity. Everything after it is the film proper and
        // obeys continuity in full; `CameraPath.titleCutS` names the instant so
        // the gate can scan from it rather than excuse a frame range.
        return Prologue(beats: collapse(wanted, config: config), transitionS: 0)
    }

    /// A `RecapBounds` in the camera math's own bounds type.
    static func bounds(of recap: RecapBounds) -> Bounds {
        Bounds(
            minLat: recap.minLat, maxLat: recap.maxLat,
            minLon: recap.minLon, maxLon: recap.maxLon
        )
    }

    /// One wide beat, centred where it can honestly claim to be.
    ///
    /// **An establishing shot that cannot hold the trip must establish where the
    /// trip begins** (2026-08-08). A wide beat is centred on the trip so the
    /// viewer sees the whole journey before it starts — but `cappedToRegion` can
    /// shrink that beat below the span the trip actually needs, because beyond the
    /// installed tiles there is nothing to draw. New Zealand is the clean case:
    /// bounds 205 km wide by 74 km tall, so the widest portrait frame that fits
    /// *inside* them is 41 km — one fifth of the trip. The beat was still centred
    /// on the trip's middle, while the body camera starts at the journey's first
    /// point 110 km away, and the "closing zoom" between them had no zoom left to
    /// do. It was a pure 2.7-frame-width pan across the country, with the car
    /// parked and nothing else on screen moving — the frame's entire contents
    /// replaced twice while the film had not yet begun.
    ///
    /// So: a beat wide enough to contain the trip keeps the containing centre and
    /// behaves exactly as before. A beat that is *not* wide enough has no wider
    /// context left to offer, and is framed on the body camera's own starting
    /// position instead — which makes the handoff into the body a zoom, or
    /// nothing at all, but never a journey across the map.
    ///
    /// This is why the fix belongs here and not in the continuity gate: the pan
    /// was never a threshold that needed relaxing, it was a beat that had lost its
    /// reason to exist and kept its motion.
    static func wideBeat(
        spanM: Double,
        route: [Point],
        tripBounds: Bounds,
        config: TrackingConfig.Export,
        containingCentre: (lat: Double, lon: Double)? = nil
    ) -> CameraFrame {
        guard spanM < fittingSpanM(bounds: tripBounds, config: config) else {
            let centre = containingCentre ?? (
                lat: (tripBounds.minLat + tripBounds.maxLat) / 2,
                lon: (tripBounds.minLon + tripBounds.maxLon) / 2
            )
            return CameraFrame(centerLat: centre.lat, centerLon: centre.lon, spanM: spanM, bearing: 0)
        }
        // Exactly where the follow camera will have settled by the time the
        // opening hands over — not the route's own framing, which is only where
        // the dolly starts before the spring has had the opening to move it.
        let start = bodyFrame(route: route, spanM: spanM, config: config)
        return CameraFrame(centerLat: start.centerLat, centerLon: start.centerLon, spanM: spanM, bearing: 0)
    }

    /// Drops beats that would not move the camera. When two consecutive framings
    /// are effectively the same picture, the later one wins — it is the one
    /// closest to the journey starting, and it carries the shorter hold, so the
    /// film gets on with it instead of sitting on a duplicate.
    static func collapse(_ beats: [Beat], config: TrackingConfig.Export) -> [Beat] {
        var kept: [Beat] = []
        for beat in beats {
            guard let previous = kept.last else { kept.append(beat); continue }
            if isEffectivelyTheSame(previous.frame, beat.frame, config: config) {
                kept[kept.count - 1] = beat
            } else {
                kept.append(beat)
            }
        }
        return kept
    }

    /// Two framings the eye cannot tell apart: near-identical zoom *and* centre.
    /// Both matter — a pan at the same zoom is still movement worth spending time
    /// on, and a zoom in place likewise.
    static func isEffectivelyTheSame(
        _ lhs: CameraFrame, _ rhs: CameraFrame, config: TrackingConfig.Export
    ) -> Bool {
        guard lhs.spanM > 0, rhs.spanM > 0 else { return true }
        let zoomRatio = max(lhs.spanM, rhs.spanM) / min(lhs.spanM, rhs.spanM)
        guard zoomRatio <= config.openingCollapseZoomRatio else { return false }
        let driftM = Geo.distanceM(
            latA: lhs.centerLat, lonA: lhs.centerLon, latB: rhs.centerLat, lonB: rhs.centerLon
        )
        return driftM <= min(lhs.spanM, rhs.spanM) * config.openingCollapseDriftFraction
    }

    /// A camera frame that fits `bounds`, floored at `camera_span_m` so a tiny
    /// extent does not zoom absurdly close.
    static func frame(for bounds: Bounds, config: TrackingConfig.Export, padding: Double) -> CameraFrame {
        CameraFrame(
            centerLat: (bounds.minLat + bounds.maxLat) / 2,
            centerLon: (bounds.minLon + bounds.maxLon) / 2,
            spanM: max(config.cameraSpanM, fittingSpanM(bounds: bounds, config: config) * padding),
            bearing: 0
        )
    }

    /// What `openingPlan` needs from the initializer — grouped so the call
    /// reads as one value instead of seven positional arguments.
    struct OpeningRequest {
        /// Built before this call, because the body span is derived from it.
        let prologue: Prologue?
        let route: [Point]
        let establishing: RecapBounds?
        let config: TrackingConfig.Export
        let bodySpanM: Double
        let totalDurationS: Double
        let journeyEndsBeforeS: Double
    }

    /// Where the opening ends and the journey begins — everything `CameraPath.init`
    /// used to compute as six separate `let`s between the body span and the
    /// journey timeline.
    struct OpeningPlan {
        let prologue: Prologue?
        let wideEndS: Double
        let openingEndsS: Double
        let revealS: Double
        let journeyEndS: Double
    }

    /// Lays out the opening and the handoff into the journey, in the order each
    /// value depends on the last: the wide beats first (they need the body span
    /// to know whether they'd collapse against it), then whether the closing
    /// zoom moves at all, then when the opening hands over to the body camera,
    /// then how long the closing reveal holds, then where the journey timeline
    /// itself ends. Pulled out of `CameraPath.init` (Chiu 2026-08-07) so that
    /// chain reads as one place rather than six `let`s threaded through the
    /// initializer.
    static func openingPlan(_ request: OpeningRequest) -> OpeningPlan {
        let route = request.route, config = request.config
        let bodySpanM = request.bodySpanM, total = request.totalDurationS
        let builtPrologue = request.prologue
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
            !isEffectivelyTheSame(
                wide.finalFrame,
                CameraPath.bodyFrame(route: route, spanM: bodySpanM, config: config),
                config: config
            )
        } ?? false
        let opening = builtPrologue == nil
            ? 0
            : min(wideEnd + (closingZoomMoves ? config.zoomTransitionS : 0), total)

        // The closing reveal is its own beat after the journey, never a zoom
        // during it: the body's span is fixed by product rule.
        let reveal = builtPrologue == nil ? 0 : config.endRevealS
        let journeyEnd = max(total - request.journeyEndsBeforeS - reveal, opening)

        return OpeningPlan(
            prologue: builtPrologue, wideEndS: wideEnd,
            openingEndsS: opening, revealS: reveal, journeyEndS: journeyEnd
        )
    }

    /// Interpolation between two framings.
    ///
    /// **Span moves geometrically, not linearly** — this is what made the opening
    /// zoom look janky. Zoom is perceived as a ratio: dropping from a 1,500 km
    /// country view to a 350 km regional one by equal metre-steps burns most of
    /// the apparent scale change in the first third and then crawls. Stepping by
    /// equal *ratios* makes the rate of apparent zoom constant, which is what
    /// every map library's flyTo does and what reads as smooth.
    ///
    /// Centre still lerps linearly; small lat/lon moves are safe here because a
    /// prologue never crosses the antimeridian, both frames coming from one
    /// region's extent.
    static func lerp(_ from: CameraFrame, _ to: CameraFrame, _ fraction: Double) -> CameraFrame {
        let span: Double
        if from.spanM > 0, to.spanM > 0 {
            span = from.spanM * pow(to.spanM / from.spanM, fraction)
        } else {
            span = from.spanM + (to.spanM - from.spanM) * fraction
        }
        return CameraFrame(
            centerLat: from.centerLat + (to.centerLat - from.centerLat) * fraction,
            centerLon: from.centerLon + (to.centerLon - from.centerLon) * fraction,
            spanM: span,
            bearing: 0
        )
    }
}
