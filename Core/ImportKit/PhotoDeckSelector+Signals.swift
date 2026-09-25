import Foundation

/// **The app's pick, once it has looked at the photographs** (ADR 2026-09-25 (d)).
///
/// Same shape as `pick`: highlights first, spread among themselves; the rest
/// spread across the whole visit. Three things change, and only for the
/// photographs the person did not star:
///
/// 1. **Utility photographs are never picked** — screenshots, receipts, documents.
/// 2. **A burst is one moment.** Consecutive photographs within
///    `duplicateDistance` of the moment's first frame collapse to one, so ten
///    frames of the same waterfall cannot take three of a deck's slots. A
///    moment that repeats a highlight already in the deck is dropped.
/// 3. **Each slot takes the best photograph near it**, not the one at its exact
///    centre: the visit's moments are divided among the slots by their nearest
///    centre, and the slot takes its highest-quality moment.
///
/// **With no signal it is `pick`, exactly.** Every photograph then is its own
/// moment, no quality ranks one above another, and the tie goes to the slot's
/// centre — the index `pick` would have taken. `StopDeckPickTests` pins that, so
/// a stop whose photographs were not on the device plays as it always did.
extension PhotoDeckSelector {
    public static func pick<Ref>(
        _ candidates: [(ref: Ref, isHighlight: Bool)],
        count: Int,
        signals: [PhotoSignal],
        duplicateDistance: Double
    ) -> [Ref] {
        guard count > 0 else { return [] }
        precondition(signals.count == candidates.count, "one signal per candidate")

        let highlightIndices = candidates.indices.filter { candidates[$0].isHighlight }
        let fromHighlights = centred(highlightIndices, count: Swift.min(count, highlightIndices.count))
        let room = count - fromHighlights.count
        guard room > 0 else { return fromHighlights.map { candidates[$0].ref } }

        let others = candidates.indices.filter { !candidates[$0].isHighlight && !signals[$0].isUtility }
        let moments = self.moments(others, signals: signals, duplicateDistance: duplicateDistance)
            .map { best(in: $0, centre: $0[$0.count / 2], signals: signals) }
            .filter { moment in
                !fromHighlights.contains { PhotoSignal.isDuplicate(signals[$0], signals[moment], within: duplicateDistance) }
            }

        var chosen: [Int] = []
        if room >= moments.count {
            chosen = moments
        } else {
            for slot in slots(moments.count, count: room) {
                // The best moment in the slot that does not repeat one already
                // taken — a view come back to later in the visit.
                let fresh = slot.members.map { moments[$0] }.filter { moment in
                    !chosen.contains { PhotoSignal.isDuplicate(signals[$0], signals[moment], within: duplicateDistance) }
                }
                guard !fresh.isEmpty else { continue }
                chosen.append(best(in: fresh, centre: moments[slot.centre], signals: signals))
            }
        }
        return (fromHighlights + chosen.sorted()).map { candidates[$0].ref }
    }

    /// Consecutive photographs grouped while each stays within `duplicateDistance`
    /// of its group's **first** frame — anchored, not chained, so a slow pan
    /// cannot walk one moment across a whole visit.
    private static func moments(_ indices: [Int], signals: [PhotoSignal], duplicateDistance: Double) -> [[Int]] {
        var groups: [[Int]] = []
        for index in indices {
            if let anchor = groups.last?.first,
               PhotoSignal.isDuplicate(signals[anchor], signals[index], within: duplicateDistance) {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }
        return groups
    }

    /// The highest-quality of `indices`; a tie — or any member without a
    /// quality score — goes to the one nearest `centre`, then the earlier.
    private static func best(in indices: [Int], centre: Int, signals: [PhotoSignal]) -> Int {
        let scored = indices.allSatisfy { signals[$0].quality != nil }
        return indices.min { lhs, rhs in
            if scored, let left = signals[lhs].quality, let right = signals[rhs].quality, left != right {
                return left > right
            }
            let leftGap = abs(lhs - centre), rightGap = abs(rhs - centre)
            return leftGap != rightGap ? leftGap < rightGap : lhs < rhs
        } ?? centre
    }

    /// `count` slots over `total` items: each slot's centre is the index `pick`
    /// samples, and every item belongs to the slot whose centre is nearest (the
    /// earlier on a tie). Contiguous, disjoint, and each holds its centre.
    private static func slots(_ total: Int, count: Int) -> [(centre: Int, members: [Int])] {
        let centres = (0..<count).map { Int((Double($0) + 0.5) * Double(total) / Double(count)) }
        var members = [[Int]](repeating: [], count: count)
        var slot = 0
        for item in 0..<total {
            while slot + 1 < count, centres[slot + 1] - item < item - centres[slot] { slot += 1 }
            members[slot].append(item)
        }
        return zip(centres, members).map { ($0, $1) }
    }

    /// `count` of `items`, one from the middle of each of `count` equal slices —
    /// `pick`'s sampling, over indices.
    private static func centred(_ items: [Int], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard count < items.count else { return items }
        return (0..<count).map { items[Int((Double($0) + 0.5) * Double(items.count) / Double(count))] }
    }
}
