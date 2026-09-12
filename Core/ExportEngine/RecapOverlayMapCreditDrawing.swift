import CoreGraphics
import Foundation

/// **The base map's credit, in the film** (ADR 2026-09-12).
///
/// An exported film drawn on OSM-derived tiles is a produced work under ODbL,
/// and the credit has to be on the work — so it is drawn here rather than left
/// to the app's About screen, which the user who receives the MP4 never sees.
///
/// ## Why Kamome draws its own instead of keeping the snapshotter's
///
/// `MLNMapSnapshotter` burns a credit into every image it returns
/// (`showsAttribution`, on by default) — bottom-right, `OpenFreeMap ©
/// OpenMapTiles Data from OpenStreetMap`, measured on the evaluation artifacts
/// at **351 × 11 px inside a 1080 × 1920 frame**. Three measured reasons it
/// cannot be the film's credit, each of which fails silently:
///
/// 1. **Crop-scaling takes it off the frame.** The render loop snapshots one
///    *station* and reprojects it onto a run of frames
///    (`RecapSnapshotStations`), so the station's own bottom edge is pushed
///    below the frame's. `SnapshotReprojection.map` puts a station pixel at
///    `(y − 960)·magnification + 960`; the credit's top row, y = 1896, leaves a
///    1920-tall frame at **magnification 1.0256**. The shipped station padding
///    is 1.03 and the budget 1.1, so every station that unions two framings —
///    which is every travelling frame in every film — is already past it. What
///    survives is exactly the stations `splitFrames` pins at magnification 1.0:
///    the settled part of each stop hold, and the frozen title beat.
/// 2. **The title beat then covers it.** `drawTitleBand` lays a scrim over the
///    bottom 27% of the frame at 0.9 alpha, full strength at the bottom edge —
///    directly over the burned-in credit, on the one beat that holds still long
///    enough to read.
/// 3. **It is not legible on a dark style anyway.** Dark glyphs on a
///    translucent light bar measured **7.11:1** contrast on Positron and
///    **2.07:1** on the dark Liberty fork — under WCAG's 3:1 floor for large
///    text, on the style Kamome is actually pursuing. And at 11 px it survives
///    the GIF's 1080 → 480 downscale as ~5 px.
///
/// So `MapLibreSnapshotProvider` turns `showsAttribution` off and Kamome draws
/// one credit it controls. That trade is only safe because the absence is
/// gated — `RecapMapCreditTests` is the other half of this file.
extension RecapOverlayRenderer {
    /// Bottom-left, pill-plated, one line.
    ///
    /// **Bottom-left, not bottom-right**, on the film's own layout rather than
    /// on the snapshotter's habit: the HUD owns both *top* corners (day on the
    /// left, distance on the right), the end card's figures are centred, and the
    /// title stack sits at 0.46 of its band — so the bottom-left is the one
    /// corner no beat competes for.
    ///
    /// **Never truncated and never fitted.** Every other string in this renderer
    /// is trip data of unknown length and shrinks to fit; this one is a fixed
    /// licence string, and a credit that shrank to fit would be a credit that
    /// could shrink to nothing.
    func drawMapCredit(_ text: String, into surface: RenderSurface) {
        guard !text.isEmpty else { return }
        let scale = surface.scale
        let tokens = style.mapCredit
        let margin = tokens.marginPx * scale
        let padding = CGSize(width: tokens.pillPaddingXPx * scale, height: tokens.pillPaddingYPx * scale)
        let fontPx = tokens.fontPx
        let pillH = fontPx * scale + padding.height * 2
        let pill = CGRect(
            x: margin, y: margin,
            width: textWidth(text, fontPx: fontPx, in: surface) + padding.width * 2, height: pillH
        )
        drawPill(pill, fill: tokens.pillColor, border: tokens.pillBorderColor, in: surface)
        drawText(
            text,
            at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height + fontPx * scale * 0.18),
            fontPx: fontPx, color: tokens.textColor, in: surface
        )
    }
}
