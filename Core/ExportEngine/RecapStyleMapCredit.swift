import CoreGraphics
import Foundation

/// **How the base map's licence notice is set** (ADR 2026-09-12).
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
    public var pillColor = CGColor(srgbRed: 0.031, green: 0.047, blue: 0.071, alpha: 0.72)
    public var pillBorderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
    public var textColor = CGColor(srgbRed: 0.882, green: 0.902, blue: 0.925, alpha: 1)
    public var pillPaddingXPx: CGFloat = 20
    public var pillPaddingYPx: CGFloat = 11
    /// Inset from the frame's bottom-left corner. Wider than the HUD's, so the
    /// notice sits clear of an edge a phone may round or a platform may crop.
    public var marginPx: CGFloat = 34

    public init() {}
}
