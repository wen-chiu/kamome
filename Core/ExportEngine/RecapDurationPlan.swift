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
    /// The clamps are guardrails, not the mechanism — on every committed fixture
    /// the formula itself binds:
    /// - floored at `camera_span_m`, so a trip round one block does not zoom to
    ///   the width of a street;
    /// - ceilinged at the whole route's own framing, so the camera never frames
    ///   ground the trip never visits. When that ceiling binds the whole route is
    ///   already on screen, so the subject barely reaches the dead-zone edge and
    ///   the body camera is **all but static** — the 2026-07-25 "held still"
    ///   behaviour, reached by this rule rather than special-cased.
    static func bodySpanM(
        routeDistanceM: Double,
        travelS: Double,
        routeBounds: CameraPath.Bounds,
        config: TrackingConfig.Export
    ) -> Double {
        let ceiling = max(
            CameraPath.fittingSpanM(bounds: routeBounds, config: config) * config.wideSpanPadding,
            config.cameraSpanM
        )
        guard travelS > 0, routeDistanceM > 0, config.cameraPanWindowFractionPerS > 0 else { return ceiling }
        let raw = routeDistanceM / (travelS * config.cameraPanWindowFractionPerS)
        return min(max(raw, config.cameraSpanM), ceiling)
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
        let opening = config.openingCountryS + config.openingRegionalS + 2 * config.zoomTransitionS

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

        // Holds are capped as a fraction of the body, so travel always gets the
        // rest; inverting that gives the body this dwell needs.
        let neededBody = askedTotal / max(config.maxHoldFraction, 0.01)
        let total = min(max(opening + neededBody + config.endCardS,
                            config.totalDurationMinS), config.totalDurationMaxS)

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
