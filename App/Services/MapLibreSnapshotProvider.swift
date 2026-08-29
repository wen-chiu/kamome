#if canImport(MapLibre)
import CoreGraphics
import CoreLocation
import Foundation
import KamomeExportEngine
import MapLibre
import UIKit

/// MapLibre base-map source for the recap (Replay MVP §2 / spec §4.5 step 2).
/// One `MLNMapSnapshotter` render per keyframe over self-hosted vector tiles +
/// a Kamome-authored style — the substrate that lets the recap be a
/// "紀念品地圖" rather than an Apple/Google map (spec §0 rule 6).
///
/// **This is the only file in the codebase that may `import MapLibre`.** It
/// mirrors the discipline that keeps `import MapKit` in `MapKitSnapshotProvider`
/// and `import Photos` in `PhotoLibraryImportSource` — the `MapRenderer`
/// protocol *is* the boundary (ADR 2026-07-19), so MapLibre types never leak
/// past here. CI enforces it (`.github/workflows/ci.yml` confinement grep).
///
/// The returned projection wraps `MLNMapSnapshot.point(for:)`, so the
/// traveled polyline lands exactly on the roads MapLibre drew — the same reason
/// the MapKit provider hands back `snapshot.point(for:)` instead of redoing the
/// mercator math (`RecapSnapshot.swift`).
///
/// `bearing` rotates the camera heading-up for the follow-cam (§4); `point(for:)`
/// carries the rotation, so overlays still land on the road. Pitch stays 0 (the
/// recap is top-down, not isometric) — extended additively if that ever changes
/// (ADR 2026-07-19, deferred gap 1).
public struct MapLibreSnapshotProvider: MapRenderer {
    public struct SnapshotError: Error {}

    /// A style file already resolved against its tiles (see `RecapMapStyle`).
    private let styleURL: URL

    public init(styleURL: URL) {
        self.styleURL = styleURL
    }

    /// Rotates the map (`MLNMapCamera.heading`), so it drives the heading-up
    /// follow cam (§4) — the substrate the anime hero car needs.
    ///
    /// **Locked to dark.** The souvenir map is a dark subtractive style sheet
    /// (`Config/RecapThemes/modern-minimal.json` — `#08111A`, `#04070C`,
    /// `#03070d`; the direction decided in `Docs/decisions.md` 2026-07-22), and
    /// there is no light variant of it. Declaring that here is what stops a
    /// light-mode device with tiles installed from drawing Kamome's light palette
    /// over a near-black map — the palette/base mismatch that produced the halo
    /// defect, in the other direction.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(supportsBearing: true, supportsHeadingUp: true, fixedAppearance: .dark)
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let center = CLLocationCoordinate2D(latitude: frame.centerLat, longitude: frame.centerLon)
        let size = CGSize(width: widthPx, height: heightPx)
        let zoom = Self.zoomLevel(spanM: frame.spanM, widthPx: widthPx, latitude: frame.centerLat)
        let styleURL = self.styleURL
        let bearing = frame.bearing

        // MLNMapSnapshotter is run-loop bound; drive it from the main queue and
        // hop back with the finished image. The snapshotter is retained by its
        // own completion closure until the render resolves.
        let (image, snapshot): (CGImage, MLNMapSnapshot) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let camera = MLNMapCamera()
                camera.centerCoordinate = center
                camera.pitch = 0
                camera.heading = bearing
                let options = MLNMapSnapshotOptions(styleURL: styleURL, camera: camera, size: size)
                options.zoomLevel = zoom
                // 1 point == 1 pixel so frame sizes and point(for:)
                // agree exactly, matching MapKitSnapshotProvider's displayScale 1.
                options.scale = 1
                let snapshotter = MLNMapSnapshotter(options: options)
                snapshotter.start { snapshot, error in
                    _ = snapshotter // keep alive until the callback fires
                    guard let snapshot, let cgImage = snapshot.image.cgImage else {
                        continuation.resume(throwing: error ?? SnapshotError())
                        return
                    }
                    continuation.resume(returning: (cgImage, snapshot))
                }
            }
        }

        return MapSnapshot(image: image) { lat, lon in
            snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    /// Web Mercator ground resolution → MapLibre zoom. MapLibre uses 512 px
    /// tiles, so the world spans 512·2^zoom px and meters-per-pixel at the
    /// equator is `C / (512·2^zoom)`, `C` = the WGS84 equatorial circumference.
    /// Solve for the zoom whose horizontal resolution makes `spanM` fill
    /// `widthPx` at scale 1. (Pure geodesy — not a tunable, like `Geo`'s
    /// meters-per-degree constant.)
    static func zoomLevel(spanM: Double, widthPx: Int, latitude: Double) -> Double {
        let equatorMeters = 2 * Double.pi * 6_378_137.0
        let metersPerPixelAtZoom0 = equatorMeters / 512
        let targetMetersPerPixel = spanM / Double(widthPx)
        let cosLat = cos(latitude * .pi / 180)
        return log2(metersPerPixelAtZoom0 * cosLat / targetMetersPerPixel)
    }
}
#endif
