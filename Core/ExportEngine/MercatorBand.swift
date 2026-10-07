import Foundation

/// **The frames a Web-Mercator substrate can draw as asked** (#223, ADR
/// 2026-10-07).
///
/// MapLibre will not show ground past its world's edge, ±85.05°. Asked for a
/// frame that reaches past it, it does two things, both VERIFIED on a real
/// snapshot (#223): it **shifts** the frame back inside, keeping the zoom, and
/// a frame taller than the whole world it first **zooms in** until the world
/// fills the frame's height (×1.4477 for 25,000 km at 40°N). Either way the
/// station snapshot no longer holds the ground the frame was planned against,
/// and `SnapshotReprojection` refuses the export.
///
/// So the film asks only for what the substrate will draw: every camera frame
/// is fitted into the band *before* a station is planned, exactly the way the
/// substrate would have moved it. A frame already inside comes back as the
/// identical value — normal films are untouched, pixel for pixel — and only
/// the rare film that holds places continents apart in one picture is moved,
/// which the export log names (Chiu 2026-10-07: 「照你建議的去做」).
///
/// The projection is MapLibre's: 512-px tiles over the WGS84 equatorial
/// circumference, the zoom chosen so `spanM` fills the width at the centre's
/// latitude (`MapLibreSnapshotProvider.zoomLevel`). Pure geodesy.
public struct MercatorBand: Equatable, Sendable {
    /// The latitude the substrate's world ends at — 85.0511…° for Web Mercator.
    public let maxLatitudeDeg: Double
    public let widthPx: Int
    public let heightPx: Int

    /// Web Mercator's own edge: the latitude whose projected y is ±π.
    public static let webMercatorMaxLatitudeDeg = atan(sinh(Double.pi)) * 180 / .pi

    public init(maxLatitudeDeg: Double, widthPx: Int, heightPx: Int) {
        self.maxLatitudeDeg = maxLatitudeDeg
        self.widthPx = widthPx
        self.heightPx = heightPx
    }

    private static let equatorM = 2 * Double.pi * 6_378_137.0

    /// Where a latitude falls in the world, 0 at the top edge of Web Mercator
    /// and 1 at the bottom.
    static func mercatorY(_ latitudeDeg: Double) -> Double {
        let phi = latitudeDeg * .pi / 180
        return 0.5 - log(tan(.pi / 4 + phi / 2)) / (2 * .pi)
    }

    static func latitude(mercatorY: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * mercatorY))) * 180 / .pi
    }

    /// The world's height in pixels at the zoom `frame` asks for.
    func worldPx(_ frame: CameraFrame) -> Double {
        Self.equatorM * cos(frame.centerLat * .pi / 180) * Double(widthPx) / frame.spanM
    }

    /// **The frame the substrate will actually draw for `frame`**: `frame`
    /// itself when it lies inside the band; otherwise the same zoom shifted
    /// toward the equator until its edge meets the band; and a frame taller than
    /// the band, zoomed in until the band fills its height, centred on it.
    ///
    /// A heading-up frame is returned unchanged: rotation turns the band test
    /// into a different shape, and the shipped film is north-up
    /// (`follow_heading_up: false`).
    public func fitted(_ frame: CameraFrame) -> CameraFrame {
        guard frame.bearing == 0, frame.spanM > 0 else { return frame }
        let height = Double(heightPx)
        let world = worldPx(frame)
        let top = Self.mercatorY(maxLatitudeDeg), bottom = Self.mercatorY(-maxLatitudeDeg)
        guard world.isFinite, world > 0, (bottom - top) * world >= height else {
            // Taller than the band: the band fills the frame, centred on it. A
            // hair of extra zoom keeps the substrate from nudging it again.
            let fittedWorld = height / (bottom - top) * (1 + 1e-9)
            let centre = Self.latitude(mercatorY: (top + bottom) / 2)
            return CameraFrame(
                centerLat: centre, centerLon: frame.centerLon,
                spanM: Self.equatorM * cos(centre * .pi / 180) * Double(widthPx) / fittedWorld,
                bearing: frame.bearing
            )
        }
        let half = height / 2 / world
        let centreY = Self.mercatorY(frame.centerLat)
        let fittedY = min(max(centreY, top + half), bottom - half)
        guard fittedY != centreY else { return frame }
        let centre = Self.latitude(mercatorY: fittedY)
        // Same zoom: the span is metres at the centre, so it follows cos(lat).
        return CameraFrame(
            centerLat: centre, centerLon: frame.centerLon,
            spanM: frame.spanM * cos(centre * .pi / 180) / cos(frame.centerLat * .pi / 180),
            bearing: frame.bearing
        )
    }

    /// Whether a substrate drawing `station` as asked holds every pixel of
    /// `frame` — the test `SnapshotReprojection` makes at render time, made here
    /// in exact Mercator so a station can be planned against it. Half a pixel of
    /// tolerance, as there.
    public func contains(_ station: CameraFrame, _ frame: CameraFrame) -> Bool {
        let world = worldPx(station)
        guard world.isFinite, world > 0, frame.spanM > 0 else { return false }
        let magnification = station.spanM / frame.spanM
        guard magnification >= 1 - 1e-9 else { return false }
        var dx = (frame.centerLon - station.centerLon) / 360 * world
        dx -= (dx / world).rounded() * world
        let dy = (Self.mercatorY(frame.centerLat) - Self.mercatorY(station.centerLat)) * world
        let slackX = Double(widthPx) / 2 * (1 - 1 / magnification) - abs(dx)
        let slackY = Double(heightPx) / 2 * (1 - 1 / magnification) - abs(dy)
        return min(slackX, slackY) * magnification >= -0.5
    }
}

extension LinearTimeline {
    /// This timeline, with every frame it hands out fitted into `band` — the
    /// substrate's own edge (`MapRendererCapabilities.maxFramableLatitudeDeg`).
    /// nil leaves every frame as the camera asked for it.
    public func fitted(into band: MercatorBand?) -> LinearTimeline {
        var copy = self
        copy.substrateBand = band
        return copy
    }

    /// What the band did to this film — the export log's line, so fitting is
    /// never silent. All zero for a film inside the band, which is nearly all.
    public struct BandReport: Equatable {
        /// Frames moved from where the camera asked.
        public let moved: Int
        /// The largest move, in pixels of the frame.
        public let worstShiftPx: Double
        /// Frames taller than the whole map, zoomed in to fit.
        public let tallerThanBand: Int
    }

    public func framesFittedIntoBand(fps: Int) -> BandReport {
        guard let band = substrateBand, fps > 0 else { return BandReport(moved: 0, worstShiftPx: 0, tallerThanBand: 0) }
        let bandHeight = MercatorBand.mercatorY(-band.maxLatitudeDeg) - MercatorBand.mercatorY(band.maxLatitudeDeg)
        var moved = 0, taller = 0, worst = 0.0
        for frame in 0..<frameCount {
            let raw = path.cameraFrame(atTime: Double(frame) / Double(fps))
            let asked = CameraFrame(
                centerLat: raw.centerLat, centerLon: raw.centerLon, spanM: raw.spanM, bearing: raw.bearing
            )
            let drawn = band.fitted(asked)
            guard drawn != asked else { continue }
            moved += 1
            if bandHeight * band.worldPx(asked) < Double(band.heightPx) { taller += 1 }
            let shift = abs(MercatorBand.mercatorY(asked.centerLat) - MercatorBand.mercatorY(drawn.centerLat))
                * band.worldPx(drawn)
            worst = max(worst, shift)
        }
        return BandReport(moved: moved, worstShiftPx: worst, tallerThanBand: taller)
    }
}
