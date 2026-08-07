import Foundation

/// Which film a trip becomes (Chiu 2026-08-07).
///
/// **One value, not a set of switches.** This replaced three independent booleans
/// — `tiering_enabled`, `uncapped_enabled`, `photo_allocation_enabled` — which
/// spelled 8 states of which exactly 3 were meaningful. The rules keeping the
/// other 5 out were ad-hoc negations scattered across `RecapComposer` and
/// `RecapDurationPlan` (`if tiering`, `if allocation && !tiering`,
/// `if uncapped && !allocation`). Nothing stopped a config setting two at once,
/// and nothing said what that would have meant.
///
/// **Adding a case is meant to break the build.** Every `switch` over this type is
/// exhaustive with no `default:`, so the compiler names every place that has to
/// make a decision about a new mode. That is the extensibility mechanism — do not
/// add a `default:` to silence it, and do not add speculative cases in advance
/// (Chiu 2026-08-06).
///
/// See `HANDOFF.md` for the open question about whether this should eventually be
/// two orthogonal enums — *which stops survive* and *how many photographs each
/// gets* are independent axes, and the next mode Chiu wants mixes them.
public enum RecapMode: String, Decodable, CaseIterable, Sendable {
    /// The slim cut. A budget-derived number of stops survive, each showing
    /// `tier_standard_photos`; the rest are dropped from the film entirely — no
    /// pin, no name, no pause. Length is bounded by `total_duration_max_s`.
    case highlight

    /// The complete record. Every stop survives, photographs are allocated 0–3 by
    /// rank, and the film has no duration ceiling — its length falls out of how
    /// many places the journey visited.
    case full
}
