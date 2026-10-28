import CoreGraphics
import Foundation

/// **The day stamp's look** (Chiu 2026-10-28, ADR 2026-10-28-a-new-day-presses-a-stamp-into-the-film).
///
/// The emotional axis (`CHARTER.md` §7): a hand-pressed ink stamp, the kind a
/// traveller collects in a notebook — a wobbling double border with Kamome's gull
/// breaking its top edge, ink that did not quite take everywhere, set slightly
/// askew. The type inside is the HUD's own face; only the stamp is drawn by hand.
///
/// Identity, so style tokens and never `TrackingConfig` keys; the timing is
/// `export.day_stamp`. Its own type because `RecapStyle` is at its 400-line budget.
/// Every value is a first cut, INFERRED, for Chiu to judge from the film.
public struct RecapDayStampStyle {
    /// Where the stamp presses before it flies into the HUD.
    public enum Position: String, CaseIterable {
        /// Just under the HUD pill, at its left edge: the stamp lands a short way
        /// up, into the slot it is about to fill.
        case underThePill = "under-pill"
        /// Centred in the frame's upper band, above the dead zone the vehicle
        /// drives in: a chapter heading, with a longer flight up to the pill.
        case upperCentre = "upper-centre"
    }

    public var position: Position = .underThePill

    /// **One ink for both appearances: vermilion, `#D9452E`** — 朱, the colour of
    /// a seal, a deeper relation of the film's accent rather than a new hue.
    ///
    /// ⚠️ **What the film shows is darker than this value.** The grade and the
    /// vignette go over all chrome (`FrameCompositor.drawAtmosphere`), and the
    /// vignette is strongest in the corner the stamp presses in. Measured on
    /// Iceland's first turn (2026-10-28, `~/Kamome-films/2026-10-28-day-stamp/`):
    /// under the pill it comes out `#962A2B`, 2.0:1 on the dark map's ground and
    /// 2.7:1 on the light map's (median); in the upper centre `#AE3131`, 3.1:1
    /// and 2.6:1. It reads by hue as much as by luminance. The accent `#FF6A3D`
    /// came out at 1.9:1 on the same light frame. Chiu judges it from the film.
    public var inkColor = CGColor(srgbRed: 0.851, green: 0.271, blue: 0.180, alpha: 1)

    /// The day, inside the stamp, at the 1080 reference width. The HUD's face.
    public var fontPx: CGFloat = 60
    /// Letter-spacing of the day, as a fraction of its size.
    public var trackingEm: CGFloat = 0.06
    /// The text's optical centre above its baseline, as a fraction of its size.
    public var textCentreEm: CGFloat = 0.36
    /// Text → the inner border.
    public var paddingXPx: CGFloat = 40
    public var paddingYPx: CGFloat = 30

    /// The heavy outer line and the fine one inside it.
    public var outerLinePx: CGFloat = 6
    public var innerLinePx: CGFloat = 2.5
    public var innerInsetPx: CGFloat = 10
    /// How square the border is: a superellipse exponent. Higher is squarer.
    public var squareness: CGFloat = 5
    /// How far the hand wanders off the line, at most.
    public var wobblePx: CGFloat = 2.2
    /// Askew, as a stamp pressed by hand is. Counter-clockwise is positive.
    public var rotationDeg: CGFloat = 6

    /// The gull on the top edge, breaking the border — the wordmark's bird.
    public var markLengthPx: CGFloat = 54

    /// The ink that did not take: this many small gaps, at most this large.
    public var speckleCount: Int = 46
    public var speckleMaxRadiusPx: CGFloat = 3.4

    /// The press: the stamp arrives this much larger, dips under its size as it
    /// meets the page, and settles.
    public var pressFromScale: CGFloat = 1.14
    public var pressUndershootScale: CGFloat = 0.97

    /// `underThePill`: the gap between the pill's bottom and the stamp's top,
    /// and the stamp's inset from the pill's left edge.
    public var underPillGapPx: CGFloat = 34
    public var underPillInsetPx: CGFloat = 6
    /// `upperCentre`: the stamp's centre, down from the frame's top edge, as a
    /// fraction of the frame's height.
    public var upperCentreFraction: CGFloat = 0.2

    public init() {}
}
