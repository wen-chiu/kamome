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
        guard config.photoAllocationEnabled else {
            return signals.map { min($0.photoCount, config.allocationMaxPhotos) }
        }
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
    /// **How many stops the film can present, derived from its own length**
    /// (ADR 2026-08-06 — `Docs/decisions.md`).
    ///
    /// A stop needs roughly `stop_presentation_s` of film to show its photographs
    /// properly, and only `max_hold_fraction` of the body is ever spent on stops.
    /// So the number of stops a film can carry is not a taste question and not a
    /// share — it falls out of the duration:
    ///
    ///     kept = (duration − opening − end card) × maxHoldFraction ÷ stopPresentationS
    ///
    /// This replaced a fixed `tier_skip_share`, which had to be hand-tuned per trip
    /// — 0.82 for Iceland's 65 stops and 0.5 for New Zealand's 20 — because a share
    /// scales with the trip while the budget does not.
    public static func keptStopCount(config: TrackingConfig.Export, durationS: Double) -> Int {
        let opening = config.openingCountryS + config.openingRegionalS + 2 * config.zoomTransitionS
        let body = Swift.max(durationS - opening - config.endCardS, 0)
        let dwellBudget = body * config.maxHoldFraction
        let cost = presentationCostS(config: config)
        guard cost > 0 else { return 0 }
        return Swift.max(Int(dwellBudget / cost), 1)
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
    public static func presentationCostS(config: TrackingConfig.Export) -> Double {
        let overhead = config.deckLabelLeadS + 2 * config.deckZoomS + 2 * config.subjectParkS
        return overhead + Double(config.tierStandardPhotos) * config.deckPhotoMinHoldS
    }

    public static func triage(
        _ signals: [Signal], config: TrackingConfig.Export, durationS: Double
    ) -> [Int?] {
        guard config.tieringEnabled, !signals.isEmpty else {
            return signals.map { min($0.photoCount, config.allocationMaxPhotos) }
        }
        // **Deterministic ranking.** Score descending, then original trip order for
        // ties — never the input order alone and never anything unordered, so the
        // same trip re-exported twice keeps the same stops. A film that reshuffled
        // between renders could not be evaluated, only re-rolled.
        let scored = signals.enumerated()
            .map { (index: $0.offset, score: score($0.element, config: config)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        let keep = Swift.min(keptStopCount(config: config, durationS: durationS), signals.count)
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
