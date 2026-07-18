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
public protocol RecapSnapshotProviding {
    func snapshot(
        centerLat: Double,
        centerLon: Double,
        spanM: Double,
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
        return MapSnapshot(image: image) { lat, lon in
            CGPoint(
                x: halfW + (lon - centerLon) * mPerDegLon * pxPerM,
                // Pixel origin top-left, north up.
                y: halfH - (lat - centerLat) * mPerDegLat * pxPerM
            )
        }
    }
}
