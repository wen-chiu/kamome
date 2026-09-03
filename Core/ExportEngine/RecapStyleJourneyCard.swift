import CoreGraphics
import Foundation

/// **How the boarding pass looks** — the Journey Card the crossing carries
/// (Chiu 2026-09-02), rebuilt on 2026-09-04 against **his own mockup**
/// (`~/Kamome-films/type2-2026-09-02/`, 登機證樣式（完整）), which was supplied
/// after the first pass shipped a layout of engineering's own.
///
/// Visual identity, so it lives in code and never in `Config/TrackingConfig.json`:
/// how a boarding pass looks is a design decision made in code review, not a
/// tunable (spec §0). Its own type rather than thirty more properties on
/// `RecapStyle`, which is at its 400-line budget.
///
/// ## What the mockup settles, and the two places this deliberately departs
///
/// Settled by it: the **stub is on the left**, the card is a wide 0.31 ticket
/// rather than a tall panel, the ends are named large with the local name
/// beneath, a dashed arc bows between them with the aircraft riding it, and a
/// hairline divides the ends from a labelled bottom row.
///
/// 🔴 **The mockup's bottom row has three fields and this draws two.** Its first
/// is `FLIGHT TIME 04:00`, and that field was **removed by decision** (Chiu
/// 2026-09-02): Kamome does not know when the aircraft left or landed, so
/// printing one is a fabricated record (`CLAUDE.md` rule 5). The instruction for
/// this rebuild was *content unchanged, layout only*, so the row keeps the
/// mockup's rhythm with the field that cannot be honestly filled left out.
/// **Do not restore it from the picture.** Same for the flight number: the
/// mockup reads `KM-523`, the decided constant is `THX-9527`.
///
/// ⚠️ **The card's orange is the mockup's `#FF6A3D`, not the film's `#FF8A5B`.**
/// `RecapStyle` warns against "three near-misses" of one accent, and this is
/// knowingly a second one — Chiu supplied the hex as part of the target. It is
/// one edit to collapse them if he would rather have one accent; flagged rather
/// than decided here.
public struct RecapJourneyCardStyle {
    // MARK: - The ticket

    /// Card width, as a fraction of the frame.
    public var widthFraction: CGFloat = 0.88
    /// Height as a fraction of its own width. **0.312, measured off the mockup**
    /// (1004 × 313) — a ticket, not a panel. The first pass shipped 0.46 and read
    /// as a card about a flight rather than as a boarding pass.
    public var aspect: CGFloat = 0.312
    /// Where the card's centre sits, as a fraction of the frame height measured
    /// from the bottom. Inside `RecapStyle.titleBandHeightFraction` (0.27), so
    /// the pass occupies the ground the title card has just vacated rather than
    /// claiming a new region of the frame.
    public var centerFraction: CGFloat = 0.155

    public var stockColor = CGColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 0.97)  // #F5F5F7
    public var cornerPx: CGFloat = 26
    public var shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
    public var shadowOffsetPx: CGFloat = 26
    public var shadowBlurPx: CGFloat = 54

    /// `#0E1116`. Near-black rather than black: printed card stock, not a screen.
    public var inkColor = CGColor(srgbRed: 0.055, green: 0.067, blue: 0.086, alpha: 1)
    /// `#8E8E93` — the small uppercase field labels and the local-language name.
    public var mutedColor = CGColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1)
    /// `#D9D9DE` — hairlines, the arc, and the dotted ground behind it.
    public var ruleColor = CGColor(srgbRed: 0.851, green: 0.851, blue: 0.871, alpha: 1)
    /// `#FF6A3D` — `FROM`/`TO`, the flight number's rule, the origin dot, and the
    /// aircraft. See the ⚠️ above: this is not `RecapStyle.routeAccent`.
    public var accentColor = CGColor(srgbRed: 1.0, green: 0.416, blue: 0.239, alpha: 1)

    // MARK: - The stub (left, per the mockup)

    /// Where the perforation falls, as a fraction of the card's width.
    public var stubFraction: CGFloat = 0.173
    public var perforationDashPx: CGFloat = 8
    public var perforationGapPx: CGFloat = 8
    /// The notch punched into each long edge where the perforation meets it —
    /// the detail that makes a rectangle read as a ticket.
    public var notchRadiusPx: CGFloat = 17
    /// The gull at the top of the stub. **`VehicleMarker.seagull`, sized and
    /// coloured at the call site and never restyled** — it is the same bird as
    /// the end card's wordmark (`HANDOFF.md` 2026-08-29 finding 5b).
    public var stubMarkLengthPx: CGFloat = 46
    /// The faint dotted disc at the foot of the stub — ticket furniture, and the
    /// only ornament on the card.
    public var stubWatermarkRadiusPx: CGFloat = 26
    /// The short rule under the flight number.
    public var stubRuleWidthPx: CGFloat = 34

    // MARK: - Type

    public var paddingPx: CGFloat = 30
    /// The end names. Fitted down when a place name is long, like every other
    /// piece of user data the film sets.
    public var regionFontPx: CGFloat = 47
    /// The local-language name under it.
    public var localFontPx: CGFloat = 21
    /// `FROM` / `TO` / `DISTANCE` / `DATE` / `FLIGHT` — all English literals, all
    /// uppercase, all tracked.
    public var labelFontPx: CGFloat = 19
    public var valueFontPx: CGFloat = 26
    /// `.16em`, the same strap tracking the stop label uses — one letter-spacing
    /// idiom in the film, not two.
    public var labelTrackingEm: CGFloat = 0.16

    // MARK: - The arc

    public var arcDashPx: CGFloat = 5
    public var arcGapPx: CGFloat = 8
    public var arcWidthPx: CGFloat = 2.5
    /// How far the arc bows above its chord, as a fraction of the chord.
    public var arcRiseFraction: CGFloat = 0.30
    /// The origin's filled dot and the destination's hollow ring.
    public var endpointRadiusPx: CGFloat = 7
    /// The aircraft glyph's length on the card.
    ///
    /// ⚠️ **Unrelated to `export.subject_length_px`**, which sizes the sprite on
    /// the *map* and is absolute against a frame span that moves 20×. This is a
    /// printed icon on a fixed-size ticket: it does not move with the frame, and
    /// the open question about the map sprite's size does not reach it.
    public var planeLengthPx: CGFloat = 40
    /// The dotted ground behind the arc — a plain dot field, **not a world map**.
    /// A drawn coastline on a card would be a picture of geography, and the one
    /// thing this card must not do is make a second claim about where places are;
    /// at this size a regular field reads the same and claims nothing.
    public var groundDotRadiusPx: CGFloat = 2
    public var groundDotPitchPx: CGFloat = 13
    public var groundDotAlpha: CGFloat = 0.5

    public init() {}
}
