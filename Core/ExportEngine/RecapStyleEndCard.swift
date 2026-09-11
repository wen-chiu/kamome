import CoreGraphics
import Foundation

/// **How the film signs off: the whole map, dimmed just enough to read type over**
/// (Chiu 2026-09-05, ADR 2026-09-05 (d)).
///
/// ## Three grounds were tried; this is the third and it is his
///
/// - a **full-frame scrim** (`chromeScrimColor` at 0.55, boosted to ~0.87 at the
///   centre) — rejected 2026-09-04: it was the only reason the map disappeared
///   under the closing stack, seconds after the reveal had opened the frame onto
///   the whole journey;
/// - a **card over the map** (ADR 2026-09-05 (c)) — built, rendered, and rejected
///   on sight: the map survived around it, but a panel is still a lid, and the
///   ending is supposed to *be* the journey;
/// - **the map, dimmed slightly, with the summary floating on it** — this one.
///   The trail, the coastline and the stop pins all stay legible. The dim exists
///   to let type read, not to push the map back.
///
/// 🔴 **The dim is per appearance and must stay so.** One alpha cannot serve
/// both: Apple Maps' light base sits around luminance 180–200, so the wash that
/// makes white type read on it turns the land grey; the dark base is already near
/// black and the same alpha would flatten what little separation it has. The two
/// values are set in `RecapStyle.modernMinimal(_:)`, never here — this type's
/// default is the neutral one the golden-frame gates render.
///
/// ⚠️ **The type carries a halo, which is what lets the dim stay this light** —
/// see `typeShadowColor`. Unplated type over the map is the film's existing idiom
/// (the stop labels and the flight-end country names read on both bases with *no*
/// wash at all); without separation of its own, the dim would have to do all the
/// work and would be back at a scrim.
public struct RecapEndCardStyle {
    /// The wash over the whole frame. **Alpha carries the strength**, and the
    /// shipped values are set per appearance; see the 🔴 above.
    public var dimColor = CGColor(srgbRed: 0.02, green: 0.04, blue: 0.07, alpha: 0.30)

    // MARK: - The figure row (KM · DAYS · STOPS)

    /// The number in each column.
    public var figureValueFontPx: CGFloat = 92
    /// The unit under it — small, uppercase, tracked, in the meta colour, so the
    /// number is what the eye lands on.
    public var figureLabelFontPx: CGFloat = 28
    /// `.16em`, the same strap tracking the stop label and the boarding pass use —
    /// one letter-spacing idiom in the film, not three.
    public var figureLabelTrackingEm: CGFloat = 0.16
    /// Between a value's baseline and its label's.
    public var figureLabelGapPx: CGFloat = 18
    /// How much of the frame's width the three columns span between them.
    public var figureRowWidthFraction: CGFloat = 0.86

    /// The closing line under the wordmark. Smaller than the wordmark by
    /// instruction (Chiu 2026-09-05) — it signs the film, it is not a heading.
    public var taglineFontPx: CGFloat = 30

    // MARK: - The halo that lets the dim stay light

    /// **A halo under every mark and letter on the closing card**, set once for
    /// the whole stack rather than per string.
    ///
    /// 🔴 **This is what buys the light dim.** The first render of this design
    /// used the stop label's shadow — tuned for 40 px type — and at 104 px the
    /// trip's name and the tagline washed straight out against Apple Maps' bright
    /// green land. The choice then is to deepen the dim, which greys the map and
    /// is the thing Chiu rejected twice, or to give the type its own separation.
    /// A blur this wide is invisible except directly behind a glyph, so the map
    /// keeps every pixel the type is not standing on.
    ///
    /// ⚠️ Set on the context around the whole stack, so the drawing calls inside
    /// must **not** be `drawShadowedText` — that sets its own shadow and would
    /// replace this one with the small label halo it was written for.
    ///
    /// ⚠️ **Tight, not diffuse.** The first value was a 30 px blur, and a halo that
    /// wide spreads too thin to define an edge — the trip's name held, and the
    /// tagline at 30 px over bright terrain did not. Half the blur at full opacity
    /// separates the letter rather than tinting the region behind it.
    public var typeShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.95)
    public var typeShadowBlurPx: CGFloat = 16

    public init() {}
}

/// How the film signs off.
///
/// A **style** choice, not a branch in the renderer: the closing beat is one of
/// the clearest places a tier can differ, and the difference is entirely visual.
/// Kept as a named treatment so the swap is a value, never an `if premium`
/// scattered through the drawing code.
public enum RecapEndCardTreatment: String, Sendable {
    /// The default, and what the free tier ships: **the whole map, dimmed
    /// slightly, with the summary floating on it** — mark, the trip's name, a row
    /// of three figures, the wordmark and its line. It was a full-frame scrim
    /// until 2026-09-04 and a card until 2026-09-05; `RecapEndCardStyle` carries
    /// all three grounds and why this is the one.
    case full
    /// A small wordmark in the corner and nothing else. The reveal still plays,
    /// so the film ends on the journey itself rather than on a panel about it.
    ///
    /// **Intended for a paid tier** (Chiu 2026-08-02). No tier system exists yet —
    /// this is the visual option existing and being swappable ahead of one, so
    /// when entitlements land they select a treatment rather than needing this
    /// built. Selected today by `export.end_card_style`.
    case minimal
}
