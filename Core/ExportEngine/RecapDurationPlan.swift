import Foundation
import KamomeConfig

/// How long the film runs, and where that time goes (Chiu 2026-07-30).
///
/// **Why this exists.** `export.target_duration_s` was a flat 30 s for every
/// trip, and holds were whatever was left after travel. On a six-stop trip that
/// worked out to **2.5 s per stop** — the photos had no time to land and the
/// journey read as a montage rather than a trip. Duration now follows the
/// content: more stops and more photos buy a longer film, bounded by a target
/// window so it never becomes a slideshow either.
///
/// **Time is deliberately not shared evenly** (Chiu 2026-07-30). A stop with
/// eight photos earns substantially more screen time than a stop with one; the
/// point is breathing room where there is something to breathe on, not uniform
/// padding. Each stop's dwell is driven by its own photo count, and the global
/// scale only steps in when the totals fall outside the window.
public struct RecapDurationPlan: Equatable {
    /// The whole film, including the opening prologue and the end card.
    public let totalS: Double
    /// The one-time establishing sequence before the journey starts.
    public let openingS: Double
    /// Per-stop dwell, indexed like the trip's stops. Already scaled to fit.
    public let stopDwellS: [Double]

    /// The journey itself — travel plus stops, after the prologue.
    public var bodyS: Double { totalS - openingS }

    /// Film seconds actually spent travelling — what is left once the prologue,
    /// the stop dwells and the end card are paid for. The camera only moves
    /// during these, so this is the denominator the body span is sized against.
    public var travelS: Double {
        max(bodyS - stopDwellS.reduce(0, +), 0)
    }

    public init(totalS: Double, openingS: Double, stopDwellS: [Double]) {
        self.totalS = totalS
        self.openingS = openingS
        self.stopDwellS = stopDwellS
    }

    /// **The body camera's span — one number per trip, fixed for the whole film**
    /// (Chiu 2026-08-01).
    ///
    /// Derived rather than configured, because the failure it prevents is a
    /// *rate* failure. The camera must cross `routeDistanceM` in `travelS`
    /// seconds; how watchable that is depends entirely on how much of a window
    /// it crosses per second. Pin that rate and the span falls out:
    ///
    ///     span = routeDistance / (travelSeconds × panRate)
    ///
    /// `camera_pan_window_fraction_per_s` is that rate — 0.35 means the view
    /// slides one full window every ~3 seconds. The same quantity is what
    /// `RecapCameraContinuityTests` measures, so the formula and its gate cannot
    /// drift apart.
    ///
    /// Deliberately **not** adaptive: not per-leg, not per-act, not city-versus-
    /// highway. Recomputing it mid-film is how the old act camera produced a 97×
    /// zoom-out three seconds before the end card. Different trips get different
    /// spans; one trip gets one span.
    ///
    /// **Derived from what the opening establishes** (Chiu 2026-08-09): the body
    /// is simply the established span divided by `target_zoom_ratio`, so the zoom
    /// the viewer sees is the thing being configured rather than a consequence of
    /// trip geometry. `establishedSpanM` is the span of the opening's *first*
    /// beat — the picture at t=0 — which is the country beat when a region has
    /// wider context to offer and the regional beat otherwise.
    ///
    /// Floored at `camera_span_m` so a trip round one block does not zoom to the
    /// width of a street, and never wider than what it establishes.
    ///
    /// **`camera_pan_window_fraction_per_s` is now a floor, not a target.** It
    /// bounds how much of the window the ground may cross per second; below that
    /// width the journey outruns the frame whatever the ratio asks for. Restored
    /// to 0.35 — the value it held before the 2026-08-02 wide baseline dropped it
    /// to 0.05, where the ceiling always won and it stopped deciding anything.
    static func bodySpanM(
        establishedSpanM: Double,
        routeDistanceM: Double,
        travelS: Double,
        config: TrackingConfig.Export
    ) -> Double {
        let asked = establishedSpanM / max(config.targetZoomRatio, 1)
        // **The pan floor, and why it is a floor now** (2026-08-09). The camera
        // crosses the route at a speed the *journey* sets, not the frame: a tight
        // frame does not slow the vehicle down, it just means more of the screen
        // is replaced each second. Below this width the ground outruns the window —
        // measured at 34.5 km per snapshot across a 57.8 km frame, which is 39%
        // of the picture surviving against a 40% floor.
        //
        // This used to be computed and then thrown away: the old code took
        // `min(max(raw, cameraSpanM), ceiling)`, so the ceiling always won and the
        // budget never bound anything. Making it a genuine lower bound is what
        // lets `target_zoom_ratio` be honoured wherever it is safe and quietly
        // yielded where it is not — a trip whose establishing shot is too tight to
        // divide simply does not zoom, rather than strobing.
        let panFloor = travelS > 0 && config.cameraPanWindowFractionPerS > 0
            ? routeDistanceM / (travelS * config.cameraPanWindowFractionPerS)
            : 0
        let floor = max(panFloor, config.cameraSpanM)
        return min(max(asked, floor), establishedSpanM)
    }

    /// **Uncapped mode** (EXPERIMENTAL, Chiu 2026-08-05): the film has no target
    /// length. Every stop gets the same beat — one photograph, held for
    /// `uncapped_photo_hold_s` — and the total is simply what that adds up to.
    ///
    /// The one thing still borrowed from the capped plan is `max_hold_fraction`,
    /// which here stops being a *cap* and becomes the film's **rhythm**: stops
    /// occupy that share of the body and travel gets the rest, so a journey with
    /// twice as many stops also gets twice as much road between them and the film
    /// keeps its shape instead of turning into a slideshow. Nothing is scaled to
    /// fit, so no stop can be squeezed under the photo floor — which is the whole
    /// point of the experiment.
    private static func uncapped(
        photoCounts: [Int], config: TrackingConfig.Export, deck: RecapDeck, opening: Double
    ) -> RecapDurationPlan {
        // **Per-stop, not one flat beat** (Chiu 2026-08-05). With the variable
        // allocator on, stops no longer cost the same: a three-photograph stop
        // needs three slots, and pricing every stop as one would under-buy the
        // film's length and put the extra photographs straight back under the
        // `deck_photo_min_hold_s` floor — the exact failure this mode exists to
        // avoid. The fixed overhead (label lead, both zoom ramps, park in and out)
        // is charged once per stop; only the slots scale.
        let overhead = deck.labelLeadS + 2 * deck.zoomS + 2 * config.subjectParkS
        let dwells = photoCounts.map { count in
            count > 0 ? overhead + Double(count) * config.uncappedPhotoHoldS : config.waypointHoldS
        }
        let holdTotal = dwells.reduce(0, +)
        guard holdTotal > 0 else {
            return RecapDurationPlan(totalS: config.totalDurationMinS, openingS: opening, stopDwellS: [])
        }
        // **Size the body against the holds the timeline will actually use.**
        // `LinearTimeline.pacing` adds a park ramp at each edge of every dwell on
        // top of what this plan returns, so a body sized from `holdTotal` alone
        // lands the real holds just *over* `max_hold_fraction`, and `CameraPath`
        // trims them back — putting the extra photographs straight back under the
        // min-hold floor. Charging for that ramp here is the difference between a
        // three-photograph stop showing three and showing two.
        let parked = holdTotal + Double(dwells.count) * 2 * config.subjectParkS
        let body = parked / max(config.maxHoldFraction, 0.01)
        // **The floor still applies.** Uncapped removes the *ceiling*, not the
        // minimum: a trip with few stops buys a short body, and travel is only
        // what is left over, so a three-stop trip across a whole country left the
        // camera a couple of seconds to cross it and `RecapCameraContinuityTests`
        // caught the strobe. Duration follows content, but content includes the
        // distance between the content.
        return RecapDurationPlan(
            totalS: max(opening + body + config.endCardS, config.totalDurationMinS),
            openingS: opening, stopDwellS: dwells
        )
    }

    /// Plans a film for `photoCounts` (one entry per stop, in trip order).
    ///
    /// 1. Each stop asks for what its content justifies: a fixed presentation
    ///    cost (park in, label lead, deck grow/shrink, park out) plus one photo
    ///    hold per photo, clamped to the configured per-stop window.
    /// 2. The body has to leave room for travel, so the asked-for dwell is
    ///    capped at `max_hold_fraction` of it — a film that is nothing but stops
    ///    has no journey in it.
    /// 3. The resulting total is clamped into the target window. Overruns scale
    ///    every dwell down proportionally, so the *relative* weight a photo-rich
    ///    stop earned survives; short films scale up the same way.
    public static func plan(
        photoCounts: [Int],
        config: TrackingConfig.Export,
        deck: RecapDeck
    ) -> RecapDurationPlan {
        // **One ease, not two, since the title card cuts** (Chiu 2026-08-31). The
        // opening is the card's held country frame, a cut, the destination beat,
        // and one closing zoom into the body — `title_card_s` + `opening_regional_s`
        // + `zoom_transition_s`. It used to be `opening_country_s` + regional +
        // *two* transitions, because the country eased into the region.
        //
        // This has to track `CameraPath.buildWideOpening` or the film budgets an
        // opening it does not have: the plan reserves these seconds and the stop
        // dwells divide what is left, so 2.5 s of phantom prologue is 2.5 s the
        // stops never get back. `opening_country_s` is no longer read by anything.
        let opening = config.titleCardS + config.openingRegionalS + config.zoomTransitionS

        switch config.recapMode {
        case .full:
            return uncapped(photoCounts: photoCounts, config: config, deck: deck, opening: opening)
        case .highlight:
            break
        }

        let asked = photoCounts.enumerated().map { index, count in
            // A stop with nothing to show is a waypoint: the route passes through
            // it, the film does not stop at it (Chiu 2026-08-04). Deliberately
            // outside `stop_dwell_min_s` — that floor protects stops that have
            // something to present, and applying it here spent six seconds of a
            // bounded film holding on a petrol station. Before this, a photo-less
            // stop was clamped up to the floor and then drew nothing for it.
            guard count > 0 else { return config.waypointHoldS }
            let earned = min(max(deck.dwellS(photoCount: count) + 2 * config.subjectParkS,
                                 config.stopDwellMinS), config.stopDwellMaxS)
            // The first stop is the journey's origin: the prologue has just
            // finished and no travel has been shown yet, so giving it a later
            // stop's full weight makes the film feel stuck right as it starts.
            return index == 0 ? earned * config.firstStopDwellScale : earned
        }
        let askedTotal = asked.reduce(0, +)

        guard askedTotal > 0 else {
            // Route-only film: no stops to dwell at, so the window's floor is
            // the whole budget and it all goes to travel.
            return RecapDurationPlan(
                totalS: config.totalDurationMinS, openingS: opening, stopDwellS: []
            )
        }

        // **Duration is bought by the stops that survived selection**
        // (Chiu 2026-08-14), not clamped into a fixed window. `StopPhotoAllocator`
        // already decided how many stops this trip earned, and each one is priced
        // at the same presentation cost that decision used — so the film is exactly
        // as long as its content, and a 65-stop trip stops producing the same 90 s
        // as a 10-stop one.
        //
        // `total_duration_max_s` deliberately does **not** apply here any more: it
        // was the ceiling that made trip size invisible, and the earned-stop cap is
        // the bound now. The floor stays — a very small trip still gets a
        // watchable minimum, and the camera needs travel time to cross the ground
        // between stops (see `uncapped` above, same reason).
        let presented = photoCounts.filter { $0 > 0 }.count
        let earnedTotal = StopPhotoAllocator.earnedDurationS(presentedStops: presented, config: config)
        let total = max(earnedTotal, config.totalDurationMinS)

        // What dwell actually fits, once the prologue and end card are paid for.
        let availableBody = max(total - opening - config.endCardS, 0)
        let allowedDwell = availableBody * config.maxHoldFraction
        let scale = askedTotal > 0 ? min(allowedDwell / askedTotal, 1.0) : 1
        // Scaling up is left alone on purpose: a short trip gets a longer,
        // calmer film through travel time rather than by inflating a one-photo
        // stop past what its content justifies.
        return RecapDurationPlan(
            totalS: total,
            openingS: opening,
            stopDwellS: asked.map { $0 * scale }
        )
    }
}
