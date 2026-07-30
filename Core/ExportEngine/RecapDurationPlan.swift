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

    public init(totalS: Double, openingS: Double, stopDwellS: [Double]) {
        self.totalS = totalS
        self.openingS = openingS
        self.stopDwellS = stopDwellS
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
        let opening = config.openingCountryS + config.openingRegionalS + config.openingRouteS
            + 2 * config.zoomTransitionS

        let asked = photoCounts.map { count in
            min(max(deck.dwellS(photoCount: count) + 2 * config.subjectParkS,
                    config.stopDwellMinS), config.stopDwellMaxS)
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
