import Foundation

/// Photo-deck pacing (§5). A stop's dwell scales with its photo count so all
/// 3–8 photos get their `photoHoldS`; the `LinearTimeline` derives a
/// grow → rotate → shrink envelope over that window. Mirrors `export.deck_*`;
/// the default matches the shipped config so a default-constructed value still
/// paces sensibly.
public struct RecapDeck {
    public var photoHoldS: Double
    public var zoomS: Double
    /// The pin/label leads (spec §5, Chiu 2026-07-24 two-beat): it lands first
    /// at the follow span, then the camera dollies in and the photos bloom.
    public var labelLeadS: Double

    public init(photoHoldS: Double = 0.8, zoomS: Double = 0.5, labelLeadS: Double = 0.6) {
        self.photoHoldS = photoHoldS
        self.zoomS = zoomS
        self.labelLeadS = labelLeadS
    }

    /// Dwell for a stop showing `photoCount` deck photos: the label lead, then a
    /// grow-in and shrink-out (zoomS each) bracketing one `photoHoldS` slot per
    /// photo. At least one slot so a single-photo stop still reads.
    public func dwellS(photoCount: Int) -> Double {
        labelLeadS + 2 * zoomS + Double(max(1, photoCount)) * photoHoldS
    }
}
