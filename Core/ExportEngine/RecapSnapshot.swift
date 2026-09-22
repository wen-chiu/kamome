import CoreGraphics
import Foundation
import KamomeTrackingEngine

/// A rendered base map plus its own geo→pixel projection (§4.5 step 2).
///
/// The projection travels with the image because only the snapshot's producer
/// knows it exactly — MKMapSnapshotter's `point(for:)` is the reason the
/// traveled polyline lands on the roads it was recorded on. Overlay drawing
/// must always project through this, never through its own mercator math.
///
/// `project` is a pure function of `(lat, lon)` for the life of one snapshot —
/// the station it was taken for never changes — and one station serves every
/// frame the render loop holds it for (`RecapSnapshotStations`). The trail
/// alone projects every vertex of the revealed route through it on every one
/// of those frames, so the same coordinate is asked for again and again;
/// `cache` answers a repeat without a second call into the provider's own
/// projection (an Obj-C round trip for `MapLibreSnapshotProvider`). Memoising
/// a pure function is bit-identical to calling it every time — this changes
/// nothing a frame draws, only how many times it is computed.
public struct MapSnapshot {
    public let image: CGImage
    private let project: (_ lat: Double, _ lon: Double) -> CGPoint
    /// Reference-shared, so every copy of this snapshot (one struct value,
    /// handed to every frame a station serves) hits the same cache. Scoped to
    /// the snapshot's own lifetime — it is released with it once the render
    /// loop evicts the station.
    private let cache = MapProjectionCache()

    public init(image: CGImage, project: @escaping (_ lat: Double, _ lon: Double) -> CGPoint) {
        self.image = image
        self.project = project
    }

    public func point(lat: Double, lon: Double) -> CGPoint {
        cache.point(lat: lat, lon: lon, project: project)
    }
}

/// `MapSnapshot.point`'s memoisation, split out because it also has to be the
/// answer to a question `MapSnapshot` alone cannot ask: whether `project`
/// itself is safe to call from more than one thread at once.
///
/// Parallel compositing (`RecapRenderLoop`) can ask the same station for two
/// different frames' points at the same time. This project's own math
/// (`FlatSnapshotProvider`) is fine with that — it touches nothing but its
/// arguments. `MapLibreSnapshotProvider`'s `project` closure is not
/// provably fine: it calls into `MLNMapSnapshot.point(for:)`, and nothing in
/// MapLibre's public surface documents that call as safe under concurrent
/// use from more than one thread. So the lock here is held **across** the
/// underlying call, not just around the dictionary — a cache miss serialises
/// every caller onto one `project` call at a time rather than risking two
/// threads inside MapLibre's Objective-C++ bridge simultaneously. Once a
/// coordinate is cached, every further reader is a lock around a dictionary
/// read, which is what makes this pay for itself rather than merely move the
/// contention.
private final class MapProjectionCache: @unchecked Sendable {
    private struct Key: Hashable {
        let lat: Double
        let lon: Double
    }

    private let lock = NSLock()
    private var storage: [Key: CGPoint] = [:]

    func point(lat: Double, lon: Double, project: (_ lat: Double, _ lon: Double) -> CGPoint) -> CGPoint {
        let key = Key(lat: lat, lon: lon)
        lock.lock()
        defer { lock.unlock() }
        if let cached = storage[key] { return cached }
        let computed = project(lat, lon)
        storage[key] = computed
        return computed
    }
}

/// Deterministic no-map background: a solid fill with a local equirectangular
/// projection centered on the camera (Layer 1 `MapRenderer`). Same inputs →
/// identical bytes, which is what the golden-frame gate tests hash against.
public struct FlatSnapshotProvider: MapRenderer {
    public struct RenderError: Error {}

    /// Rotates its projection for `bearing`, so heading-up stays deterministic.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(supportsBearing: true, supportsHeadingUp: true)
    }

    /// sRGB fill for the empty map.
    private let background: CGColor

    public init(red: CGFloat = 0.93, green: CGFloat = 0.93, blue: CGFloat = 0.91) {
        background = CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let centerLat = frame.centerLat, centerLon = frame.centerLon, spanM = frame.spanM, bearing = frame.bearing
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
