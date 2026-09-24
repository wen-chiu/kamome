import Foundation

/// Picks the photographs a stop shows in its recap deck (spec §4.5 / §5).
/// Pure and deterministic, so the same trip re-exported keeps the same decks.
/// Story Director's Vision scoring (reopened by Chiu 2026-09-24) will rank
/// within the same shape: highlights, then the rest across the visit.
public enum PhotoDeckSelector {
    /// How many photographs a stop's deck shows once the person's own picks are
    /// counted (Chiu 2026-09-24): what the stop was allocated, raised to cover its
    /// highlights, but never past `highlightCap` on their account — "however much
    /// you love a place, five photographs". A stop allocated more than the cap
    /// keeps its allocation; the cap bounds what highlights can *add*.
    public static func deckCount(allocated: Int, highlights: Int, highlightCap: Int) -> Int {
        Swift.max(allocated, Swift.min(highlights, Swift.max(highlightCap, 0)))
    }

    /// Picks `count` of a stop's photographs (Chiu 2026-09-24).
    ///
    /// `candidates` is **every** photograph at the stop, time-ordered. Highlights
    /// come first; when there are more of them than `count`, they are themselves
    /// spread across the visit. Whatever room is left goes to the other
    /// photographs, spread across the *whole* visit.
    ///
    /// This replaces "spread eight, then keep the first N", which kept the first
    /// N of eight evenly spaced picks: at three photographs, only the first ~30%
    /// of a visit could ever reach the film, its very first frame always did, and
    /// a highlight past the first was only kept if it happened to land on a
    /// sampled index.
    ///
    /// Sampling is **centred** — the middle of each of `k` equal slices — so a
    /// visit's first frame (the car park, the sign, the ticket) is not
    /// guaranteed a place. Result: highlights in time order, then the rest in time
    /// order, so the deck still leads with a highlight. Deterministic, never
    /// repeats.
    public static func pick<Ref>(_ candidates: [(ref: Ref, isHighlight: Bool)], count: Int) -> [Ref] {
        guard count > 0 else { return [] }
        let highlights = candidates.filter(\.isHighlight).map(\.ref)
        let others = candidates.filter { !$0.isHighlight }.map(\.ref)
        let fromHighlights = centred(highlights, count: Swift.min(count, highlights.count))
        let fromOthers = centred(others, count: Swift.min(count - fromHighlights.count, others.count))
        return fromHighlights + fromOthers
    }

    /// `count` items from `items`, one from the middle of each of `count` equal
    /// slices, in order.
    private static func centred<Ref>(_ items: [Ref], count: Int) -> [Ref] {
        guard count > 0 else { return [] }
        guard count < items.count else { return items }
        return (0..<count).map { slice in
            items[Int((Double(slice) + 0.5) * Double(items.count) / Double(count))]
        }
    }
}
