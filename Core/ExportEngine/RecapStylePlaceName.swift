import CoreGraphics
import Foundation

/// **How the trip's own towns are named on the map** (Chiu 2026-10-02, ADR file
/// 2026-10-02).
///
/// Identity, so these are style tokens in code and never `TrackingConfig` keys —
/// the rule the rest of `RecapStyle` follows. Its own type because `RecapStyle`
/// is at its 400-line budget, the split `RecapFlightEndStyle` already makes.
public struct RecapPlaceNameStyle {
    /// The name, at the 1080 reference width.
    ///
    /// The flight ends' country names are set at the same size in the same
    /// shadowed face: both are the ground the film is read against, and neither
    /// is a stop. Smaller than a stop's name (76), which is where the film
    /// pauses; larger than any name the base map draws (its towns reach 28).
    public var fontPx: CGFloat = 44

    /// **The name is set as a map sets a name: ink, and a halo of the ground
    /// under it** — not the shadowed white of a stop's name, which was made for
    /// type over a photograph. Judged on renders of both shipped maps
    /// (2026-10-02): white with a drop shadow read on the dark map and was a
    /// grey smudge on the light one, and on either it let the trail run through
    /// the letters. The halo cuts the trail and the terrain away from the
    /// glyphs, and the pair follows the appearance like the trail does.
    ///
    /// These are the dark map's: the HUD's own off-white, on the halo the dark
    /// style gives its own labels. `modernMinimal(.light)` sets the light pair.
    public var textColor = CGColor(srgbRed: 0.953, green: 0.961, blue: 0.969, alpha: 1)
    public var haloColor = CGColor(srgbRed: 0.043, green: 0.078, blue: 0.102, alpha: 0.9)
    /// How far the halo reaches past the glyph.
    public var haloPx: CGFloat = 5

    /// Line to line, for a name set on two lines.
    public var lineHeightEm: CGFloat = 1.12

    /// Past this width a name of several words is set on two lines: a national
    /// park's full name would otherwise span most of the frame.
    public var maxWidthPx: CGFloat = 430

    /// The dot that says where the name's town is.
    public var dotRadiusPx: CGFloat = 8

    /// Dot → name. Enough that the vehicle parked on the town's stop does not
    /// stand on its name.
    public var dotGapPx: CGFloat = 36

    /// The room each name keeps around itself. Two names closer than this are
    /// one too many, and the second is not drawn.
    public var clearancePx: CGFloat = 18

    public init() {}
}
