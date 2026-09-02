import Foundation
import KamomeConfig

/// **Which of the three films this trip is** (Chiu 2026-09-01).
///
/// 1. **local** — one region, no crossing. What ships today.
/// 2. **oneDestination** — home, then one destination abroad. Fly out, then the
///    trip at the destination.
/// 3. **multiRegion** — several crossings. Deferred; it is a loop over 2 rather
///    than a new mechanism, so it is recognised here and built later.
///
/// ## The rule is distinct local journeys — not crossings, and not countries
///
/// Both of the obvious signals have a counter-example that is a real trip:
///
/// - **counting crossings** misclassifies a round trip. Taiwan → Japan → Taiwan
///   is two crossings and *one* destination.
/// - **counting countries** misclassifies a domestic flight. Tokyo → Miyakojima
///   is one country and is still a journey to a destination.
///
/// So the unit is the **local journey**: a run of legs with road under all of
/// it. `SegmentRoutability.noRoad` already partitions a trip into them, and this
/// counts the distinct ones — folding a journey that returns to a region an
/// earlier one already covered, which is what makes the round trip come out at
/// two rather than three.
///
/// **`CountryExtent` is deliberately not consulted.** It can *name* a region for
/// the title card; it must not be the identity, or Tokyo → Miyakojima collapses
/// to one journey and the film loses its flight.
///
/// ## Derived, never stored
///
/// The brief asked for a schema column on the `stop.kind` pattern. **That
/// pattern's precondition does not hold here** (Chiu agreed, 2026-09-01):
/// `stop.kind` is established at import from data fully present at import, while
/// this depends on `segment.routability`, which detached background routing may
/// write days later *by design* (ADR 2026-08-15). A value stamped at import
/// would be stamped before its input exists, and would then need a second write
/// path to stay true — the silently-degrading shape `Arch.md` §6 names. Derived
/// at compose time it reads whatever routing has established by the moment the
/// film is made, which is the only correct answer.
///
/// Two consequences, recorded rather than solved (`HANDOFF.md`): the same trip
/// yields different films on different days, and nothing yet tells a user that
/// re-exporting later would give a better one.
public enum RecapFilmType: Equatable, Sendable {
    case local
    case oneDestination
    case multiRegion
    /// **Routing has not answered for every leg, so a crossing may be hiding in
    /// one.** Not a fourth kind of film — it is the refusal to claim one of the
    /// three, and it renders as `local` while saying so in the log.
    ///
    /// Its own case rather than a default to `.local` for the reason
    /// `SegmentRoutability` refuses to read NULL as `noRoad`: "we never found
    /// out" is a third state, and collapsing it into an answer is a claim about
    /// the journey. The difference is visible — a caller can tell the user the
    /// film will improve, which a silent `.local` cannot.
    case unknown

    /// The form the film actually takes.
    ///
    /// `unknown` renders the local film, because the honest reading of "we do not
    /// know whether you flew" is "do not draw a flight" — the same rule
    /// `RecapTrip.Leg.isCrossing` already follows one level down.
    ///
    /// ⚠️ **`multiRegion` renders the type-2 form**, because the multi-region film
    /// is deferred and a trip with three local journeys is still, in every part
    /// the type-2 form draws, a journey out to somewhere else. It flies the first
    /// crossing and lets the rest play as arcs in the body, which is what happens
    /// today. **Revisit when type 3 opens** — see `classify`.
    public var renderedForm: RecapFilmType {
        switch self {
        case .unknown: return .local
        case .multiRegion: return .oneDestination
        case .local, .oneDestination: return self
        }
    }

    /// Whether this trip's film shows a journey to somewhere else.
    public var hasDestinationAbroad: Bool {
        renderedForm == .oneDestination || renderedForm == .multiRegion
    }

    /// Classify a trip from its legs in travel order.
    ///
    /// ## The reading is monotonic, and that is what makes it useful
    ///
    /// An unrouted leg can only ever **add** a local journey — if it turns out to
    /// be a crossing it splits a run in two; it can never merge two runs into
    /// one. So `distinctJourneyCount` over the *confirmed* crossings is a **lower
    /// bound**, and a lower bound of 2 is already a fact: whatever the unknowns
    /// turn out to be, this trip has at least two local journeys.
    ///
    /// This claims strictly less than it knows and degrades safely, and it is
    /// what stops `unknown` from swallowing every trip. **The first version of
    /// this function returned `unknown` whenever any leg was NULL**, which sounded
    /// careful and was not: routing ships disabled and the offline gate
    /// establishes nothing, so every fixture classified `unknown`, fell back to
    /// the local film, and **the type-2 form would have had no test coverage at
    /// all** — the fifth instance in this project of a property that only exists
    /// on the shipping path being guarded only where the shipping path is not.
    ///
    /// ⚠️ **`>= 2` maps to the type-2 form, and that is sound only while type 3 is
    /// deferred.** A lower bound of 2 could still resolve to 3, and today both
    /// render the same way, so nothing is claimed that could be wrong. **The day
    /// the multi-region film is built, this collapses two different answers into
    /// one and must be revisited** — a lower bound of 2 with unknowns outstanding
    /// will no longer be enough to choose between them.
    ///
    /// - Parameter everyLegEstablished: whether routing answered — with any of its
    ///   three verdicts — for **every** leg. It only decides the *bottom* of the
    ///   range now: with no confirmed crossing, a trip is `local` if nothing is
    ///   outstanding and `unknown` if something still is.
    public static func classify(legs: [RecapTrip.Leg], everyLegEstablished: Bool) -> RecapFilmType {
        switch distinctJourneyCount(legs: legs) {
        case ...1: return everyLegEstablished ? .local : .unknown
        case 2: return .oneDestination
        default: return .multiRegion
        }
    }

    /// How many distinct local journeys the trip contains.
    ///
    /// Split at every crossing, discard the crossings themselves (a crossing is
    /// the join, not a journey), then fold any journey whose ground a previous
    /// one already covered.
    ///
    /// **The fold is bounding-box intersection, and it is threshold-free on
    /// purpose.** "Within N km of an earlier journey" would be a number nobody
    /// could later justify, reverse-derived from whichever trip it was tuned on —
    /// how `body_span_padding` and `tier_skip_share` were both built and both
    /// removed. Two boxes either share ground or they do not.
    public static func distinctJourneyCount(legs: [RecapTrip.Leg]) -> Int {
        var journeys: [[RecapCoordinate]] = []
        var current: [RecapCoordinate] = []
        for leg in legs {
            if leg.isCrossing {
                if !current.isEmpty { journeys.append(current) }
                current = []
            } else {
                current.append(contentsOf: leg.coordinates)
            }
        }
        if !current.isEmpty { journeys.append(current) }

        // A trip may legitimately open or close on a crossing (`Docs/camera-arcs.md`
        // §4 Case C), which is why empty runs are dropped above rather than counted.
        var regions: [RecapBounds] = []
        for journey in journeys {
            guard let box = enclosing(journey) else { continue }
            if let index = regions.firstIndex(where: { intersects($0, box) }) {
                // A return to ground already visited is the same region, widened
                // by whatever of it this visit newly covered.
                regions[index] = union(regions[index], box)
            } else {
                regions.append(box)
            }
        }
        return regions.count
    }

    private static func enclosing(_ coordinates: [RecapCoordinate]) -> RecapBounds? {
        guard let first = coordinates.first else { return nil }
        var bounds = RecapBounds(
            minLat: first.lat, minLon: first.lon, maxLat: first.lat, maxLon: first.lon
        )
        for coordinate in coordinates.dropFirst() {
            bounds = RecapBounds(
                minLat: min(bounds.minLat, coordinate.lat), minLon: min(bounds.minLon, coordinate.lon),
                maxLat: max(bounds.maxLat, coordinate.lat), maxLon: max(bounds.maxLon, coordinate.lon)
            )
        }
        return bounds
    }

    private static func intersects(_ lhs: RecapBounds, _ rhs: RecapBounds) -> Bool {
        lhs.minLat <= rhs.maxLat && rhs.minLat <= lhs.maxLat
            && lhs.minLon <= rhs.maxLon && rhs.minLon <= lhs.maxLon
    }

    private static func union(_ lhs: RecapBounds, _ rhs: RecapBounds) -> RecapBounds {
        RecapBounds(
            minLat: min(lhs.minLat, rhs.minLat), minLon: min(lhs.minLon, rhs.minLon),
            maxLat: max(lhs.maxLat, rhs.maxLat), maxLon: max(lhs.maxLon, rhs.maxLon)
        )
    }
}
