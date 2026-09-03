import CoreGraphics
import Foundation

/// **How the boarding pass looks** — the Journey Card the crossing carries
/// (Chiu 2026-09-02).
///
/// Visual identity, so it lives in code and never in `Config/TrackingConfig.json`:
/// how a boarding pass looks is a design decision made in code review, not a
/// tunable (spec §0, the same rule the rest of `RecapStyle` follows). Its own type
/// rather than twenty more properties on `RecapStyle`, which was already at its
/// 400-line budget — the same split `RecapStylePresets` and the four
/// `RecapOverlay*Drawing` files already make.
///
/// **A light ticket over a dark film, deliberately.** Everything else drawn over
/// the map is light type on a dark wash. A boarding pass is a *printed object*,
/// and printing it is what makes it read as an artefact rather than as more
/// chrome. It sits in the band the title card has just vacated, which is clear by
/// the time the crossing starts.
///
/// ⚠️ **The layout these tokens describe is engineering's, not the reviewed
/// target.** The review names Chiu's own "登機證樣式（完整）" ticket as the visual
/// reference and says to save it beside the film; it is not in
/// `~/Kamome-films/type2-2026-09-02/`. The content is exactly what was decided;
/// the arrangement is a first pass and is expected to be judged.
public struct RecapJourneyCardStyle {
    /// Card width, as a fraction of the frame.
    public var widthFraction: CGFloat = 0.84
    /// Card height as a fraction of its own width — a ticket, not a panel.
    public var aspect: CGFloat = 0.46
    /// Where the card's centre sits, as a fraction of the frame height measured
    /// from the bottom. Inside `RecapStyle.titleBandHeightFraction` (0.27), so the
    /// pass occupies the title's ground rather than claiming a new region of the
    /// frame.
    public var centerFraction: CGFloat = 0.155

    public var stockColor = CGColor(srgbRed: 0.976, green: 0.973, blue: 0.961, alpha: 0.97)
    public var cornerPx: CGFloat = 28
    public var shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
    public var shadowOffsetPx: CGFloat = 26
    public var shadowBlurPx: CGFloat = 54

    /// Ink. Near-black rather than black: printed card stock, not a screen.
    public var inkColor = CGColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1)
    /// The small uppercase field labels (`FROM`, `TO`, `DISTANCE`) and the
    /// secondary local-language name — present, never competing with the ink.
    public var mutedColor = CGColor(srgbRed: 0.42, green: 0.46, blue: 0.51, alpha: 1)
    /// The one coloured element: the flight number, and the aircraft on the arc.
    /// The film's own accent, so the pass belongs to this film.
    public var accentColor = RecapStyle.routeAccent

    /// Where the perforated stub begins, as a fraction of the card's width.
    public var stubFraction: CGFloat = 0.72
    public var perforationDashPx: CGFloat = 9
    public var perforationGapPx: CGFloat = 9
    /// The notch punched into each long edge where the perforation meets it —
    /// the detail that makes a rectangle read as a ticket.
    public var notchRadiusPx: CGFloat = 18
    public var paddingPx: CGFloat = 34

    // Type sizes at the 1080 reference width, scaled with it like every other
    // token in `RecapStyle`.
    public var regionFontPx: CGFloat = 46
    public var localFontPx: CGFloat = 26
    public var labelFontPx: CGFloat = 20
    public var valueFontPx: CGFloat = 28
    public var flightFontPx: CGFloat = 34
    /// `.16em` — the same strap tracking the stop label uses. One letter-spacing
    /// idiom in the film, not two.
    public var labelTrackingEm: CGFloat = 0.16

    /// The dotted arc between the two ends, and the aircraft riding it.
    public var arcDashPx: CGFloat = 6
    public var arcGapPx: CGFloat = 10
    public var arcWidthPx: CGFloat = 3
    /// How far the arc bows above its chord, as a fraction of the chord.
    public var arcRiseFraction: CGFloat = 0.22
    /// The aircraft glyph's length, drawn on the card.
    ///
    /// ⚠️ **Unrelated to `export.subject_length_px`**, which sizes the sprite on
    /// the *map* and is absolute against a frame span that moves 20×. This is a
    /// printed icon on a fixed-size ticket: it does not move with the frame, and
    /// the open question about the map sprite's size does not reach it.
    public var planeLengthPx: CGFloat = 34

    public init() {}
}
