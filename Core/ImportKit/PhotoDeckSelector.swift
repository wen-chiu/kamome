import Foundation

/// Picks the 3–8 photos a stop shows in its recap deck (spec §4.5 / §4.7
/// Stage 2; prototype `choose_named_stops`). Deterministic: evenly spread
/// across the visit so the deck samples the whole stop, not just its first
/// burst. This is the MVP's *basic* selection — Story Director (Phase 4) will
/// rank by salience instead (spec §7), so keep this pure and swappable.
public enum PhotoDeckSelector {
    /// Evenly spreads picks across `assetIds` (already time-ordered): all of
    /// them when few, else `count` samples at even fractional indices. Result
    /// preserves order and never repeats.
    public static func evenlySpread(_ assetIds: [String], min minCount: Int, max maxCount: Int) -> [String] {
        let total = assetIds.count
        guard total > 0 else { return [] }
        let want = Swift.max(minCount, Swift.min(maxCount, total))
        guard total > want else { return assetIds }
        guard want > 1 else { return [assetIds[0]] }

        var picked: [String] = []
        var seen = Set<String>()
        for step in 0..<want {
            let index = Int((Double(step) * Double(total - 1) / Double(want - 1)).rounded())
            let asset = assetIds[index]
            if seen.insert(asset).inserted { picked.append(asset) }
        }
        return picked
    }
}
