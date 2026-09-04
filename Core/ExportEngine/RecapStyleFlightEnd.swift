import CoreGraphics
import Foundation

/// **How the two ends of a flight are marked** (Chiu 2026-09-04, ADR
/// 2026-09-04) — the mark on each end of a type-2 film's crossing, and the
/// country name beneath it.
///
/// Identity, so these are style tokens in code and never `TrackingConfig` keys
/// (spec §0, the rule the rest of `RecapStyle` follows). Its own type because
/// `RecapStyle` is at its 400-line budget — the same split
/// `RecapJourneyCardStyle` already makes.
///
/// **What these are for.** At 8,891 km MapKit labels neither city and neither
/// coastline is a recognisable silhouette, so the opening frame is a texture
/// rather than a place — the closeout's *"the wide flight frame loses the
/// viewer"*. The marks say *here* and *there*; the names say which countries
/// those are. Nothing else on the map gains a label.
public struct RecapFlightEndStyle {
    /// The mark's drawn length at the 1080 reference width.
    ///
    /// Larger than the stop pin it stands beside in the film's other beats,
    /// because at this span it is the only thing on the frame saying *here* — and
    /// smaller than the subject, which is the thing that moves.
    public var markLengthPx: CGFloat = 92

    /// The country name under the mark.
    ///
    /// Smaller than a stop's name: a stop is where the film pauses, and this is
    /// only the ground the opening is read against. Set in the same shadowed
    /// unplated face the stop labels use, so the two read as one film rather than
    /// as two labelling systems.
    public var nameFontPx: CGFloat = 44

    public init() {}
}
