import Foundation

/// **Round 5 of the Liberty fork: fewer peaks, and the end of the style
/// evaluation** (Chiu 2026-09-15; ADR 2026-09-09, addendum 2026-09-15).
///
/// Round 4 bought the terrain Chiu asked for and he kept it — 「效果很好」. What it
/// also did was label every summit it could find: a dozen-plus names on one
/// frame, which he read as 「訊息過多對影片確實不好,可以留幾座大山訊息就好」. So
/// this round does one thing to the map — **it takes peaks away** — and closes the
/// evaluation.
///
/// ⚠️ **Two premises from round 4's brief were disproved by decoding the tiles,
/// and neither is re-derived here** (they are in the addendum):
///
/// 1. `rank <= 2` never hid Hekla. Hekla is `class=volcano`, `ele=1491`,
///    **`rank=1`**, present in the z8 tile the `iceland` frame draws from — so
///    *relaxing* the filter could only add competitors, which is what it did.
/// 2. **`rank` cannot separate an islet from an island**: Árnes `rank=3`,
///    伊良部島 `rank=4`, 竹富島 `rank=5`. Any threshold that drops the islet drops
///    two real islands with it, so **islands are not filtered by `rank`** here.
///
/// ⚠️ Still evaluation only, still a harness resource. The trail is **settled and
/// needs no code**: light → orange, dark → cyan, no glow, which is exactly what
/// ships (ADR 2026-08-27). Nothing in this file touches it.
extension LibertyFork {
    /// Which summits keep their name: an elevation floor, and optionally a rank
    /// ceiling. `nil` in `forkedRound5(from:peaks:)` means **no peaks at all** —
    /// Chiu's authorised fallback, deferred to a hiking feature rather than
    /// compromised down to a number nobody chose.
    struct PeakBand: Equatable {
        let minimumElevationM: Int
        let maximumRank: Int?
    }

    /// The search, and its answer.
    ///
    /// Round 4 drew 12+ names on `iceland` with `ele >= 600, rank <= 3`. The target
    /// Chiu set is **roughly 3–5**, so these three bands were rendered on that one
    /// frame and counted before anything else was re-rendered.
    enum Round5 {
        /// `ele >= 1000` and the top rank only.
        static let bandA = PeakBand(minimumElevationM: 1000, maximumRank: 1)
        /// `ele >= 900`, top rank only.
        static let bandB = PeakBand(minimumElevationM: 900, maximumRank: 1)
        /// `ele >= 900`, two ranks.
        static let bandC = PeakBand(minimumElevationM: 900, maximumRank: 2)

        /// **The band the four delivered frames use.** Set from the count on
        /// `iceland`, not from taste — see `Docs/handoff-openfreemap-eval.md`.
        static let chosen = bandA
    }

    /// Round 4 (hillshade on) with the peaks narrowed to `peaks`, or removed when
    /// it is nil.
    ///
    /// The island filter loses its `rank` clause here, for the measured reason at
    /// the top of this file: `rank` does not mean "is a real island".
    static func forkedRound5(from stock: [String: Any], peaks: PeakBand?) throws -> [String: Any] {
        var style = try forkedRound4(from: stock, hillshade: true, peaks: .rankAtMost3)
        guard var layers = style["layers"] as? [[String: Any]] else { throw ForkError.noLayers }

        let peakIDs = ["mountain-peak-dot", "mountain-peak-name"]
        guard layers.contains(where: { peakIDs.contains($0["id"] as? String ?? "") }) else {
            throw ForkError.unexpectedShape("round 4 drew no peak layers for round 5 to narrow")
        }
        if let peaks {
            layers = layers.map { narrowed($0, to: peaks, ids: peakIDs) }
        } else {
            layers.removeAll { peakIDs.contains($0["id"] as? String ?? "") }
        }
        layers = try islandsWithoutRank(layers)
        style["layers"] = layers
        return style
    }

    static func resolvedRound5StyleURL(peaks: PeakBand?) throws -> URL {
        let name = peaks.map { "e\($0.minimumElevationM)r\($0.maximumRank.map(String.init) ?? "any")" } ?? "none"
        return try write(
            try forkedRound5(from: try stockStyle(), peaks: peaks),
            named: "kamome-liberty-fork-r5-\(name).json"
        )
    }

    private static func narrowed(_ layer: [String: Any], to band: PeakBand, ids: [String]) -> [String: Any] {
        guard ids.contains(layer["id"] as? String ?? "") else { return layer }
        var layer = layer
        var filter: [Any] = ["all", [">=", ["get", "ele"], band.minimumElevationM]]
        if let rank = band.maximumRank { filter.append(["<=", ["get", "rank"], rank]) }
        layer["filter"] = filter
        return layer
    }

    /// **Islands keep their size and their placement, and lose the rank clause.**
    ///
    /// Round 4 filtered them by `rank <= 2` to keep Iceland's river islet Árnes out
    /// of the frame. The tiles say that cannot work: the islet ranks *above* two
    /// genuine islands. An unfiltered island layer draws Árnes at island size on
    /// `iceland`, which is the honest cost of not having a rule — recorded rather
    /// than papered over with a threshold that means nothing.
    private static func islandsWithoutRank(_ layers: [[String: Any]]) throws -> [[String: Any]] {
        guard let index = position(of: "label_island", in: layers) else {
            throw ForkError.unexpectedShape("no `label_island` to unfilter")
        }
        var layers = layers
        layers[index]["filter"] = ["==", ["get", "class"], "island"] as [Any]
        return layers
    }
}
