import Foundation
import KamomeConfig

/// How many photographs each stop gets to show (**EXPERIMENTAL**, Chiu 2026-08-05).
///
/// Replaces "every stop gets the same number" with "every stop gets what it
/// earned". A stop you photographed twice on the way past gets a pin, a name and
/// a moment; the one you spent an afternoon at gets three pictures.
///
/// **Ranked shares, not thresholds.** The 2026-08-04 attempt used absolute cuts
/// and failed: a real trip's stops carry anywhere from 2 to 252 photographs, so
/// any absolute threshold either demotes almost nothing or almost everything, and
/// the right value differs per trip. What *is* stable across trips is the shape —
/// a few places you photographed heavily, a long tail you barely did. So stops are
/// ranked against each other and the film's attention is divided by share.
///
/// A useful property: the shares fix the photo budget at roughly one photograph
/// per stop on average (0.3×1 + 0.2×2 + 0.1×3 = 1.0), so film length stays a
/// predictable function of stop count even though individual stops vary.
///
/// **Signals used, and the one that is missing.**
/// - *Photograph count* — available everywhere, the primary signal.
/// - *Favourites* (`PHAsset.isFavorite`) — an explicit judgement by the person who
///   was there, so it is worth `favorite_weight` ordinary photographs. Available
///   only where a real photo library is: on device. **Desk fixtures carry place
///   and time only, and exported JPEGs hold no rating tag** (measured: 0 of 2300
///   Iceland photographs), so a desk pilot ranks on count alone and its ordering
///   is a lower bound on what the app will do.
/// - *Dwell time* — deliberately **not** used. Imported trips only know the span
///   between the first and last photograph at a place, which is a proxy for
///   photographing, not for staying. Real dwell needs passive capture (Capture
///   Beta) and is the natural upgrade to this scorer when it lands: it would enter
///   as a third term here and nothing else would have to change.
public enum StopPhotoAllocator {
    /// One stop's evidence of attention.
    public struct Signal: Equatable {
        public let photoCount: Int
        public let favoriteCount: Int

        public init(photoCount: Int, favoriteCount: Int = 0) {
            self.photoCount = photoCount
            self.favoriteCount = favoriteCount
        }
    }

    /// Photographs per stop, in the order given.
    ///
    /// Ties are broken by original order so the result is deterministic — a
    /// requirement for golden-frame CI and for re-exporting the same film twice.
    public static func allocate(_ signals: [Signal], config: TrackingConfig.Export) -> [Int] {
        guard !signals.isEmpty else { return [] }

        let scored = signals.enumerated()
            .map { (index: $0.offset, score: score($0.element, config: config)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        // Rank 0 is the most-photographed stop, so the cuts are laid out from the
        // top down. The top band is whatever the three configured shares leave
        // over — the shares name the *quiet* end, because that is the end whose
        // size actually needs controlling.
        let count = Double(signals.count)
        let zeroShare = clampedShare(config.allocationZeroShare)
        let oneShare = clampedShare(config.allocationOneShare)
        let twoShare = clampedShare(config.allocationTwoShare)
        let maxCut = 1.0 - max(1.0 - (zeroShare + oneShare + twoShare), 0)
        let twoCut = maxCut - twoShare
        let oneCut = twoCut - oneShare

        var result = [Int](repeating: 0, count: signals.count)
        for (rank, entry) in scored.enumerated() {
            let fraction = 1.0 - Double(rank) / count
            let photos: Int
            switch fraction {
            case let value where value > maxCut: photos = config.allocationMaxPhotos
            case let value where value > twoCut: photos = 2
            case let value where value > oneCut: photos = 1
            default: photos = 0
            }
            // Never promise more pictures than the stop actually has.
            result[entry.index] = min(photos, entry.score > 0 ? signals[entry.index].photoCount : 0)
        }
        return result
    }

    /// **Variant B triage** (Chiu 2026-08-06): skip / standard / top.
    ///
    /// Returns `nil` for a stop the film should **drop entirely** — no pin, no
    /// name, no pause, no park beat. That is the decisive difference from
    /// `allocate`, whose zero-photo stops still halt the story to name themselves.
    /// Here the car drives straight past and the route is the only evidence the
    /// journey went through.
    ///
    /// The top tier needs **both** signals: a rank inside `tier_top_share` *and* at
    /// least one favourited photograph. Rank alone would just be "most photographs",
    /// which is already what standard rewards; the favourite is the person saying so
    /// out loud. Consequence worth knowing before reading any desk render: fixtures
    /// carry no favourites, so **the top tier is empty in every pilot** and only a
    /// real photo library can fill it.
    /// **How many stops a trip earns**, from how big the journey was
    /// (Chiu 2026-08-14 — inverts the 2026-08-06 ADR).
    ///
    /// This replaced `keptStopCount(config:durationS:)`, which derived the count
    /// from the film's duration. That direction was self-defeating in Variant B:
    /// duration was clamped to the same 60–90 s window for every trip, so trip size
    /// never entered the model and a 10-stop day and a 65-stop fortnight both
    /// presented exactly 8 stops. Reversing it puts trip size in one named place
    /// and lets duration fall out (`RecapDurationPlan.plan`).
    ///
    ///     earned = floor + perDoubling × log2(tripStops ÷ referenceTripStops)
    ///
    /// clamped to `[floor, cap]`. Sub-linear by construction: each *doubling* of
    /// the trip earns a fixed increment, so a 65-stop trip earns more film than a
    /// 10-stop one without earning 6.5× of it.
    ///
    /// **Two properties worth stating, because they are what make a reverse-derived
    /// rule survivable.** It cannot explode on a huge trip (the cap binds past ~36
    /// stops) and cannot collapse on a tiny one (the floor binds below the
    /// reference, and `triage` then takes the minimum against the stops that
    /// actually exist). And there is **no division to floor**, which is what
    /// produced Iceland's `21.999999999999996` off-by-one under the old direction.
    ///
    /// ⚠️ **The slope rests on one observation.** Of the three approved films,
    /// Miyakojima (10 → 8) coincides with the floor and Iceland (65 → 21) is decided
    /// by the cap, so **New Zealand at 20 → 15 is the only trip actually sitting on
    /// the curve.** `earned_stops_per_doubling` is therefore fitted to a single
    /// point, and the only range where it decides anything is roughly **10–36
    /// stops** — below that the floor answers, above it the cap does. The next real
    /// trip that lands in that range is the slope's first genuine validation; until
    /// then, treat a change to it as changing New Zealand's film and nothing else.
    public static func earnedStopCount(tripStopCount: Int, config: TrackingConfig.Export) -> Int {
        guard tripStopCount > 0 else { return 0 }
        let reference = Swift.max(config.earnedStopsReferenceTripStops, 1)
        let doublings = log2(Double(tripStopCount) / Double(reference))
        let earned = Double(config.earnedStopsFloor) + config.earnedStopsPerDoubling * doublings
        let bounded = Swift.min(Swift.max(earned.rounded(), Double(config.earnedStopsFloor)),
                                Double(config.earnedStopsCap))
        return Int(bounded)
    }

    /// The film length a presented-stop count buys — the inverse direction of the
    /// same cost model, and the only place a Variant B duration is decided.
    ///
    ///     duration = opening + end card + (stops × presentationCost) ÷ maxHoldFraction
    public static func earnedDurationS(presentedStops: Int, config: TrackingConfig.Export) -> Double {
        let opening = config.openingCountryS + config.openingRegionalS + 2 * config.zoomTransitionS
        let dwell = Double(presentedStops) * presentationCostS(config: config)
        return opening + config.endCardS + dwell / Swift.max(config.maxHoldFraction, 0.01)
    }

    /// What one presented stop costs in **dwell** seconds.
    ///
    /// Derived, not configured, because every term is already a tunable and a
    /// second hand-set constant would drift away from them. A stop pays a fixed
    /// presentation overhead — the label lead, both deck zoom ramps, the car
    /// parking and pulling away — plus one `deck_photo_min_hold_s` slot per
    /// photograph it is meant to show. Anything less and the deck is truncated
    /// back under the floor, which is the failure this whole policy exists to stop.
    ///
    /// Worth keeping straight: this is dwell seconds, and dwell is only
    /// `max_hold_fraction` of the body. At the shipped values a stop costs 5.4 s of
    /// dwell, which is about 9–10 s of *film* — the "~10 s per stop" figure from
    /// the earlier duration studies. Same law, different denominator; dividing the
    /// dwell budget by the film-seconds number is what made the first attempt
    /// return half as many stops as the measurements said (2026-08-06).
    /// **Prices the expected mix, not the worst case** (Chiu asked for a deliberate
    /// choice, 2026-08-14). `triage` gives the top `tier_top_share` of stops
    /// `tier_top_photos` rather than `tier_standard_photos`, so charging every stop
    /// the standard rate under-budgets any trip whose library has favourites — by
    /// roughly 10 s on a 210 s film. Fixtures carry no favourites, so the top tier
    /// is empty in every desk render and this could not show up here.
    ///
    /// Worst-case pricing (every stop at the top rate) was rejected because
    /// `tier_top_share` makes it unreachable by construction: it would inflate
    /// every film for a case that cannot occur. The expected mix is derived from
    /// the same two tunables that create the tiers, so it adds no constant of its
    /// own and cannot drift away from them.
    ///
    /// **Why this is the safe direction to be wrong in.** `tier_top_share` is a
    /// *ceiling*, not a quota, and the top tier additionally requires the stop to
    /// have a favourite — so the true mean photo count is **at or below** the 3.3
    /// this prices, never above it. Pricing at 3.3 therefore systematically
    /// over-charges: a film buys slightly more dwell than its stops end up
    /// spending, and lands a little short of its budget rather than over it. Under
    /// -charging would push the deck past what the film can hold, which is the
    /// truncation this whole policy exists to prevent.
    public static func presentationCostS(config: TrackingConfig.Export) -> Double {
        let overhead = config.deckLabelLeadS + 2 * config.deckZoomS + 2 * config.subjectParkS
        let topShare = clampedShare(config.tierTopShare)
        let photos = (1 - topShare) * Double(config.tierStandardPhotos)
            + topShare * Double(config.tierTopPhotos)
        return overhead + photos * config.deckPhotoMinHoldS
    }

    /// **No `durationS` parameter any more.** It used to take the film's length and
    /// derive the stop count from it; the trip now earns the count and the length
    /// follows, so passing a duration here would reintroduce the circularity the
    /// inversion removed.
    public static func triage(
        _ signals: [Signal], config: TrackingConfig.Export
    ) -> [Int?] {
        guard !signals.isEmpty else { return [] }
        // **Deterministic ranking.** Score descending, then original trip order for
        // ties — never the input order alone and never anything unordered, so the
        // same trip re-exported twice keeps the same stops. A film that reshuffled
        // between renders could not be evaluated, only re-rolled.
        let scored = signals.enumerated()
            .map { (index: $0.offset, score: score($0.element, config: config)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        let keep = Swift.min(earnedStopCount(tripStopCount: signals.count, config: config), signals.count)
        let topCut = 1.0 - clampedShare(config.tierTopShare)
        let count = Double(signals.count)

        var result = [Int?](repeating: nil, count: signals.count)
        for (rank, entry) in scored.enumerated() where rank < keep {
            let fraction = 1.0 - Double(rank) / count
            let signal = signals[entry.index]
            let wanted = (fraction > topCut && signal.favoriteCount > 0)
                ? config.tierTopPhotos
                : config.tierStandardPhotos
            result[entry.index] = Swift.min(wanted, signal.photoCount)
        }
        return result
    }

    /// A stop's attention score: its photographs, plus each favourite counted
    /// `favorite_weight` times over. A favourite is already counted once as a
    /// photograph, so the weight is a *bonus* rather than a replacement.
    private static func score(_ signal: Signal, config: TrackingConfig.Export) -> Double {
        Double(signal.photoCount) + Double(signal.favoriteCount) * config.favoriteWeight
    }

    private static func clampedShare(_ share: Double) -> Double {
        Swift.min(Swift.max(share, 0), 1)
    }
}
