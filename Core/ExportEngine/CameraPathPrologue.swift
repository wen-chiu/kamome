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
    /// `bodySpanM` is passed only so a wide beat that already frames the body
    /// tightly can collapse against it; the body's own framing stays live.
    static func buildWideOpening(
        route: [Point],
        establishing: RecapBounds?,
        config: TrackingConfig.Export,
        bodySpanM: Double
    ) -> Prologue {
        let tripBounds = bounds(of: route)
        let regionalAsked = frame(for: tripBounds, config: config, padding: config.wideSpanPadding)
        // Same cap as the body: a trip covering most of its region asks for more
        // frame than there are tiles to fill it with.
        let regional = wideBeat(
            spanM: cappedToRegion(regionalAsked.spanM, establishing: establishing, config: config),
            route: route, tripBounds: tripBounds, config: config
        )

        let countryBounds: Bounds
        if let establishing {
            countryBounds = Bounds(
                minLat: min(establishing.minLat, tripBounds.minLat),
                maxLat: max(establishing.maxLat, tripBounds.maxLat),
                minLon: min(establishing.minLon, tripBounds.minLon),
                maxLon: max(establishing.maxLon, tripBounds.maxLon)
            )
        } else {
            countryBounds = tripBounds
        }
        // **The country beat is framed to fit *inside* the region, not to contain
        // it** (2026-08-02). Framing to contain, then padding, puts the tiles'
        // own edge on screen: outside them there is no water layer, only the
        // style's background, so the data boundary draws itself as a lighter
        // rectangle across the establishing shot. Fitting within the extent shows
        // as much of the country as a portrait frame can hold and never a pixel
        // of nothing.
        //
        // Without an extent there are no tiles to fall off, so the trip's own
        // bounds are widened by `country_view_padding` as before — the most an
        // offline app can claim to know about the surrounding geography.
        let country = establishing == nil
            ? frame(for: countryBounds, config: config, padding: config.countryViewPadding)
            : wideBeat(
                spanM: max(config.cameraSpanM, containedSpanM(bounds: countryBounds, config: config)),
                route: route, tripBounds: tripBounds, config: config,
                containingCentre: (
                    lat: (countryBounds.minLat + countryBounds.maxLat) / 2,
                    lon: (countryBounds.minLon + countryBounds.maxLon) / 2
                )
            )

        // A region cut tightly around one trip is not a wider context — framed to
        // fit inside its own extent it can come out *narrower* than the trip's
        // padded view, which would open the film by zooming out and then back in.
        // When the region has nothing wider to say, the country beat is simply not
        // built, and the regional view carries the title.
        let countryAddsContext = country.spanM > regional.spanM * config.openingCollapseZoomRatio
        let wanted = countryAddsContext
            ? [
                Beat(frame: country, holdS: config.openingCountryS),
                Beat(frame: regional, holdS: config.openingRegionalS)
            ]
            // The title always belongs to the first beat, whichever that is.
            : [Beat(frame: regional, holdS: config.openingCountryS)]
        return Prologue(beats: collapse(wanted, config: config), transitionS: config.zoomTransitionS)
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
        let route: [Point]
        let establishing: RecapBounds?
        let config: TrackingConfig.Export
        let bodySpanM: Double
        let openingS: Double
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
        let route = request.route, establishing = request.establishing, config = request.config
        let bodySpanM = request.bodySpanM, total = request.totalDurationS
        // The wide beats only. The old third beat — a *stored* frame of the
        // first act — is gone: the opening now zooms into the live follow
        // camera, so the two can never disagree at the seam.
        let builtPrologue = request.openingS > 0
            ? buildWideOpening(route: route, establishing: establishing, config: config, bodySpanM: bodySpanM)
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
