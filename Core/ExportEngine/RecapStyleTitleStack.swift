import CoreGraphics
import Foundation

/// **How the opening title's stack is set** — brand lockup, the trip's name, a
/// short rule, then its dates (2026-11-03). The band it stands on and the
/// name's own size stay in `RecapStyle`; this holds what the stack added.
public struct RecapTitleStackStyle {
    /// The mark shrinks inside the band — branding signs the opening, it is not
    /// the subject of it. 0.55 until 2026-11-03.
    public var markScale: CGFloat = 0.45
    /// The wordmark beside the mark on the opening — a signature, set below the
    /// date line's size so the trip's name is the first thing read (2026-11-03).
    public var brandFontPx: CGFloat = 30
    public var brandTrackingEm: CGFloat = 0.06
    /// The short accent rule between the trip's name and its dates — the mark's
    /// colour, so the opening carries one warm stroke besides the brand.
    public var ruleWidthPx: CGFloat = 72
    public var ruleHeightPx: CGFloat = 4
    /// The date and distance line under the name: smaller than the old 40 and
    /// tracked, so it reads as a caption to the name rather than a second title.
    public var metaFontPx: CGFloat = 34
    public var metaTrackingEm: CGFloat = 0.08
    /// 🔴 **The least room between the title stack and the top of the map
    /// credit** (2026-11-03). The credit wraps to as many lines as its licence
    /// needs — three for a European film (#114) — and the stack used to be
    /// placed as though it were one, so the dates sat under the Copernicus
    /// sentence. The stack rises, and its band with it, by whatever this needs.
    public var creditClearancePx: CGFloat = 44

    // MARK: - The entrance (2026-11-03)

    /// The title used to cut in whole on frame 0 and cut out on the beat's last
    /// frame — a still, not an opening. Now the band settles, then the mark,
    /// the name, the rule drawing outward and the dates arrive in turn, and the
    /// whole stack fades as the map takes over.
    ///
    /// ⏳ **Authored for the shipped 3 s beat** (`title_card_s`), on the desk,
    /// not yet judged in a film on the phone. A shorter beat compresses every
    /// time below in proportion, so the stack always settles and always leaves.
    public var choreographyReferenceS: Double = 3.0
    /// The band's own fade in, from the beat's first frame.
    public var bandInS: Double = 0.6
    /// When each element starts to arrive, from the beat's first frame.
    public var brandStartS: Double = 0.2
    public var nameStartS: Double = 0.4
    public var ruleStartS: Double = 0.85
    public var metaStartS: Double = 1.05
    /// How long one element takes to arrive — fade and rise together, eased out.
    public var elementInS: Double = 0.7
    /// How far an element rises into place as it arrives.
    public var risePx: CGFloat = 22
    /// The whole stack, band included, fades over the beat's last this-many s.
    public var exitS: Double = 0.5

    public init() {}
}
