import CoreGraphics
import Foundation
import KamomeTrackingEngine

/// A rendered base map plus its own geo→pixel projection (§4.5 step 2).
///
/// The projection travels with the image because only the snapshot's producer
/// knows it exactly — MKMapSnapshotter's `point(for:)` is the reason the
/// traveled polyline lands on the roads it was recorded on. Overlay drawing
/// must always project through this, never through its own mercator math.
public struct MapSnapshot {
    public let image: CGImage
    private let project: (_ lat: Double, _ lon: Double) -> CGPoint

    public init(image: CGImage, project: @escaping (_ lat: Double, _ lon: Double) -> CGPoint) {
        self.image = image
        self.project = project
    }

    public func point(lat: Double, lon: Double) -> CGPoint {
        project(lat, lon)
    }
}

/// Where base maps come from. `MapKitSnapshotProvider` is the shipping
/// implementation; `FlatSnapshotProvider` keeps the pipeline deterministic
/// for golden-frame tests and offline route-only renders.
///
/// `bearing` (deg, 0 = north-up) rotates the map heading-up for the follow-cam
/// (§4). Providers that can't rotate (the retiring MapKit path) ignore it; the
/// camera path only emits a non-zero bearing when `export.follow_heading_up` is
/// on, which requires the MapLibre substrate.
public protocol RecapSnapshotProviding {
    func snapshot(
        centerLat: Double,
        centerLon: Double,
        spanM: Double,
        bearing: Double,
        widthPx: Int,
        heightPx: Int
    ) async throws -> MapSnapshot
}

/// Deterministic no-map background: a solid fill with a local equirectangular
/// projection centered on the camera. Same inputs → identical bytes, which is
/// what the golden-frame gate tests hash against.
public struct FlatSnapshotProvider: RecapSnapshotProviding {
    public struct RenderError: Error {}

    /// sRGB fill for the empty map.
    private let background: CGColor

    public init(red: CGFloat = 0.93, green: CGFloat = 0.93, blue: CGFloat = 0.91) {
        background = CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    public func snapshot(
        centerLat: Double,
        centerLon: Double,
        spanM: Double,
        bearing: Double,
        widthPx: Int,
        heightPx: Int
    ) async throws -> MapSnapshot {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: widthPx,
                  height: heightPx,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw RenderError() }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
        guard let image = context.makeImage() else { throw RenderError() }

        // Local meters-per-degree measured at the camera, not hardcoded.
        let mPerDegLat = Geo.distanceM(latA: centerLat - 0.5, lonA: centerLon, latB: centerLat + 0.5, lonB: centerLon)
        let mPerDegLon = Geo.distanceM(latA: centerLat, lonA: centerLon - 0.5, latB: centerLat, lonB: centerLon + 0.5)
        let pxPerM = Double(widthPx) / spanM
        let halfW = Double(widthPx) / 2
        let halfH = Double(heightPx) / 2
        // Heading-up: rotate the north-up screen offset by -bearing, so a point
        // in the travel direction lands straight above center. cos/sin of 0 are
        // 1/0, so the north-up path (bearing 0) is byte-identical to before.
        let theta = -bearing * .pi / 180
        let cosT = cos(theta)
        let sinT = sin(theta)
        return MapSnapshot(image: image) { lat, lon in
            // North-up screen offset from center (pixel origin top-left).
            let sx = (lon - centerLon) * mPerDegLon * pxPerM
            let sy = -(lat - centerLat) * mPerDegLat * pxPerM
            return CGPoint(
                x: halfW + sx * cosT - sy * sinT,
                y: halfH + sx * sinT + sy * cosT
            )
        }
    }
}
