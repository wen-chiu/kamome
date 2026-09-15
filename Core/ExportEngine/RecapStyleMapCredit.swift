import CoreGraphics
import Foundation

/// **How the base map's licence notice is set** (ADR 2026-09-12 (b)).
///
/// Drawn in the frame's bottom-left on every frame of every export, *after* the
/// grade and the vignette — `RecapOverlayMapCreditDrawing` carries the drawing
/// and the three measurements that put it there.
///
/// ⏳ **A defensible default, not a design.** Sized and coloured off the HUD's
/// pill — the one idiom in this film already proven to stay legible over an
/// arbitrary photograph — then set smaller, because a licence notice is not
/// chrome and must not compete with the two numbers that are. What it should
/// finally look like is `DESIGNER.md`'s, and this type is where that work lands.
///
/// **Bottom-left is a layout fact, not a habit.** The HUD owns both *top*
/// corners (day on the left, distance on the right), the end card's figures are
/// centred, and the title stack sits at `titleStackCenterFraction` 0.46 of its
/// band — so the bottom-left is the one corner no beat competes for.
public struct RecapMapCreditStyle {
    /// ⚠️ **This has a floor, and the GIF sets it.** Every export surface
    /// composites the same frame and the GIF then scales it to
    /// `export.gif_width_px` (480 of 1080), so a credit legible in the MP4 can
    /// arrive ~5 px tall in the other file the app writes — which is exactly
    /// what `MLNMapSnapshotter`'s own burned-in copy measured, and one of the
    /// three reasons it could not be the film's credit.
    /// `RecapMapCreditTests.testTheCreditStaysLegibleAfterTheGifDownscale`
    /// holds the product of the two.
    public var fontPx: CGFloat = 24

    // MARK: - The plate

    /// **Lightened 2026-09-13, and the type was not touched** (ADR 2026-09-13).
    /// Chiu asked twice whether the credit could be smaller. The *type* cannot
    /// move — `fontPx` 24 × 480/1080 is 10.67 px in the GIF against a floor of
    /// 10, so 22.5 is the entire headroom and the gate goes red at 22.4 — so the
    /// weight came out of the plate instead: padding 20/11 → 14/8 (pill height
    /// 46 → 40) and the fill from 0.72 alpha to 0.55.
    ///
    /// 🔴 **VERIFIED 2026-09-13 on rendered frames**, not eyeballed. The text is
    /// opaque, so only the *plate* moves with what is under it. Text-on-plate
    /// contrast, `iceland` at 1080×1920, against a 4.5:1 floor:
    ///
    /// | | dark Liberty fork, title beat | Positron light, travelling beat |
    /// |---|---|---|
    /// | 0.72 (before) | 15.64:1 | — not rendered |
    /// | **0.55 (shipped)** | **15.66:1** | **7.51:1** |
    ///
    /// The reason any of this is drawn at all is that `MLNMapSnapshotter`'s own
    /// burned-in credit measured **2.07:1** on this same dark style. A lighter
    /// plate is a preference; legibility is the obligation.
    ///
    /// ⚠️ **The dark ground cannot tell you anything, and the light one's margin
    /// is partly the theme's.** Over a near-black map the plate is near-black at
    /// every alpha — the dark column reads ~15:1 whatever this value is. And the
    /// credit draws *after* `drawAtmosphere`, so on a light map it sits on
    /// ground `modern-minimal` has already graded (0.16) and vignetted (0.42):
    /// back-solving the measured plate puts the ground under this corner at
    /// ~140 luma, not Positron's own 242.
    ///
    /// **COMPUTED, not measured** — on a light theme with *no* atmosphere the
    /// same 0.55 plate would give **3.75:1** and fail the floor. No such theme
    /// exists today. So: do not lower this further, and if a theme ever drops
    /// its grade or vignette, re-measure **on a light ground**.
    public var pillColor = CGColor(srgbRed: 0.031, green: 0.047, blue: 0.071, alpha: 0.55)
    public var pillBorderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
    public var textColor = CGColor(srgbRed: 0.882, green: 0.902, blue: 0.925, alpha: 1)
    public var pillPaddingXPx: CGFloat = 14
    public var pillPaddingYPx: CGFloat = 8
    /// Inset from the frame's bottom-left corner. Wider than the HUD's, so the
    /// notice sits clear of an edge a phone may round or a platform may crop.
    ///
    /// 🔴 **34 is a floor, not a preference** (ADR 2026-09-13 §c). With a 40 px
    /// pill this puts the credit at y 1846…1886 of a 1080×1920 frame, and a
    /// platform centre-cropping 9:16 to 1:1 keeps only y 420…1500 — to 4:5, only
    /// y 285…1635. Either drops the credit entirely. That is a third party's act
    /// on a work that left Kamome carrying its credit, not a defect here; it is
    /// also why the notice must not be pushed further into the corner.
    public var marginPx: CGFloat = 34

    public init() {}
}
