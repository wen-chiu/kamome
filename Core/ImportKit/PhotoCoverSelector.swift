import Foundation

/// Picks the photographs a journey card shows (Journey Discovery, 2026-09-17).
/// Sibling of `PhotoDeckSelector`, and pure for the same reason: the same rule
/// serves a stored trip and a journey that has not been imported yet.
public enum PhotoCoverSelector {
    /// One photograph the card can show.
    public struct Candidate: Equatable, Sendable {
        public let assetId: String
        /// A favourite or a user highlight — the person who was there said this
        /// one mattered, so it leads.
        public let isHighlight: Bool

        public init(assetId: String, isHighlight: Bool) {
            self.assetId = assetId
            self.isHighlight = isHighlight
        }
    }

    /// Highlights first, in time order, then the rest spread evenly across the
    /// journey so the card samples the whole of it rather than its first burst.
    /// `ordered` is time-ordered. Never repeats an asset.
    public static func select(_ ordered: [Candidate], count: Int) -> [String] {
        guard count > 0, !ordered.isEmpty else { return [] }
        var picked: [String] = []
        for candidate in ordered where candidate.isHighlight && picked.count < count {
            if !picked.contains(candidate.assetId) { picked.append(candidate.assetId) }
        }
        let remaining = ordered.map(\.assetId).filter { !picked.contains($0) }
        let want = min(count - picked.count, remaining.count)
        guard want > 0 else { return picked }
        for step in 0..<want {
            let index = want == 1
                ? 0
                : Int((Double(step) * Double(remaining.count - 1) / Double(want - 1)).rounded())
            if !picked.contains(remaining[index]) { picked.append(remaining[index]) }
        }
        return picked
    }
}
