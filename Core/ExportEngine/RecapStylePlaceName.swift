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
