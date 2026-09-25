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

    /// The one owner of every snapshotter this process has in flight.
    static let snapshotters = MainThreadLeases<MLNMapSnapshotter>()

    /// What the current export has asked of MapLibre: counts and durations only
    /// (`MapSubstrateMeter`). Reset and read by the export job.
    static let meter = MapSubstrateMeter()

    /// MapLibre's network hook holds its delegate weakly, so this is its owner.
    private static let networkProbe = NetworkProbe(meter: meter)

    /// **Sizes the tile cache and starts counting requests.** Called on the main
    /// queue before an export's first snapshot. MapLibre asks for the cache size
    /// to be set before a style loads, and its completion runs synchronously on
    /// main. Setting the same size again is cheap, so every export calls this.
    /// It changes when a tile is downloaded, never what is drawn.
    @MainActor
    static func prepareForExport(cacheMb: Int) async -> Error? {
        MLNNetworkConfiguration.sharedManager.delegate = networkProbe
        meter.reset()
        return await withCheckedContinuation { continuation in
            MLNOfflineStorage.shared.setMaximumAmbientCacheSize(UInt(max(0, cacheMb)) * 1_048_576) { error in
                continuation.resume(returning: error)
            }
        }
    }

    /// Counts the requests MapLibre sends and hands each back **unchanged**:
    /// this only observes. Called on MapLibre's own background threads; the
    /// meter is lock-guarded. (There is no response side: MapLibre 6.27 never
    /// calls `didReceiveResponse:`, `MapSubstrateMeter`.)
    private final class NetworkProbe: NSObject, MLNNetworkConfigurationDelegate {
        let meter: MapSubstrateMeter

        init(meter: MapSubstrateMeter) {
            self.meter = meter
        }

        // Selector pinned: this is an optional requirement, and a Swift name
        // that missed the Objective-C one would compile and silently never run.
        @objc(willSendRequest:)
        func willSend(_ request: NSMutableURLRequest) -> NSMutableURLRequest {
            let conditional = request.value(forHTTPHeaderField: "If-None-Match") != nil
                || request.value(forHTTPHeaderField: "If-Modified-Since") != nil
            meter.requestSent(url: request.url, conditional: conditional)
            return request
        }
    }

    /// Times one snapshot from start to style-loaded and to completion. The
    /// snapshotter holds its delegate weakly; the completion block owns this.
    private final class SnapshotTiming: NSObject, MLNMapSnapshotterDelegate {
        private let lock = NSLock()
        private let started = ContinuousClock.now
        private var styleLoadedS: Double?

        @objc(mapSnapshotter:didFinishLoadingStyle:)
        func mapSnapshotter(_ snapshotter: MLNMapSnapshotter, didFinishLoading style: MLNStyle) {
            lock.lock()
            defer { lock.unlock() }
            styleLoadedS = Self.seconds(since: started)
        }

        func finish(succeeded: Bool) {
            lock.lock()
            let style = styleLoadedS
            lock.unlock()
            MapLibreSnapshotProvider.meter.snapshotFinished(
                totalS: Self.seconds(since: started), styleS: style, succeeded: succeeded
            )
        }

        private static func seconds(since instant: ContinuousClock.Instant) -> Double {
            let elapsed = ContinuousClock.now - instant
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        }
    }

    /// A style file already resolved against its tiles (see `RecapMapStyle`).
    private let styleURL: URL

    /// The appearance the style at `styleURL` **is**, which the palette drawn over
    /// it must follow. Defaults to `.dark`, which is what the one shipping style
    /// sheet is — see `capabilities`.
    private let appearance: RecapAppearance

    /// **What a film drawn on these tiles must credit** — the string, not a
    /// flag, because this one provider serves two different hosts of the same
    /// OpenStreetMap data (the parked `.pmtiles` regions and OpenFreeMap's
    /// hosted planet) and they ask to be named differently
    /// (`RecapMapAttribution`).
    ///
    /// 🔴 **No default.** A defaulted credit is the shape of bug this whole
    /// change exists to close: whichever string happened to be nearest would be
    /// stamped onto whatever tiles the next substrate serves, and a *wrong*
    /// provenance claim is worse than a missing one (`CLAUDE.md` rule 5). Every
    /// construction site says which data it is drawing.
    private let attribution: String

    /// Whether this provider vetoes the device's appearance choice. **nil** when
    /// the caller already selected the right style sheet for the requested
    /// appearance (the OpenFreeMap path, which has both dark and light), non-nil
    /// when the style sheet has only one variant (the dormant souvenir map).
    private let fixedAppearance: RecapAppearance?

    public init(
        styleURL: URL, appearance: RecapAppearance = .dark,
        fixedAppearance: RecapAppearance? = nil, attribution: String
    ) {
        self.styleURL = styleURL
        self.appearance = appearance
        self.fixedAppearance = fixedAppearance
        self.attribution = attribution
    }

    /// Rotates the map (`MLNMapCamera.heading`), so it drives the heading-up
    /// follow cam (§4) — the substrate the anime hero car needs.
    ///
    /// `fixedAppearance` is **nil** on the OpenFreeMap path (both appearances
    /// exist; ADR 2026-09-16) and **`.dark`** on the dormant souvenir path
    /// (the dark subtractive style sheet has no light variant). When nil, the
    /// device's appearance passes through and ADR 2026-08-27 holds.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(
            supportsBearing: true, supportsHeadingUp: true, fixedAppearance: fixedAppearance,
            attribution: attribution
        )
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let center = CLLocationCoordinate2D(latitude: frame.centerLat, longitude: frame.centerLon)
        let size = CGSize(width: widthPx, height: heightPx)
        let zoom = Self.zoomLevel(spanM: frame.spanM, widthPx: widthPx, latitude: frame.centerLat)
        let styleURL = self.styleURL
        let bearing = frame.bearing

        // MLNMapSnapshotter is run-loop bound; drive it from the main queue and
        // hop back with the finished image.
        //
        // 🔴 **Its lifetime is owned by `MainThreadLeases`, never by its own
        // completion block** (device crash 2026-09-23, `EXC_BAD_ACCESS` in
        // MapLibre on the main run loop, two minutes into a 134-station export).
        // This used to read `_ = snapshotter` inside the block, which made the
        // block the last owner. MapLibre releases that block on a background
        // dispatch queue after calling it, so the snapshotter's `dealloc` — which
        // tears down its render thread and blocks on a `std::future` — ran off
        // the main thread while the main run loop was still servicing the same
        // snapshotter's sources: a use-after-free that fires only when the two
        // interleave, which is why short films never showed it. The crash
        // report's thread 13 is exactly that `dealloc`, reached from
        // `_Block_release` on `com.apple.root.default-qos`.
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
                // **Kamome draws the credit, so the snapshotter must not draw a
                // second one** (ADR 2026-09-12 (b)). Measured, not assumed: the
                // burned-in copy is 351 x 11 px at the image's bottom-right, and
                // `RecapSnapshotStations` reprojects this image onto a run of
                // frames — which pushes that corner off the frame above
                // magnification 1.026, leaves it under the title band on the one
                // beat that keeps it, and renders it at 2.07:1 contrast on the
                // dark style. `RecapOverlayMapCreditDrawing` carries the three
                // measurements. Turning it off is what stops a film from
                // carrying two credits on a stop beat and one on none of the
                // others.
                //
                // ⚠️ **`showsAttribution = false` is safe only because the film
                // draws its own and `RecapMapCreditTests` holds it to that.** If
                // that gate is ever removed, this line is the thing that has to
                // go back first.
                options.showsAttribution = false
                // The MapLibre wordmark, which the library's own header calls
                // "not required". It sits bottom-left, where Kamome's credit now
                // goes, and it credits the *renderer* rather than the data — so
                // it is not part of the obligation this change is about.
                options.showsLogo = false
                let snapshotter = MLNMapSnapshotter(options: options)
                let lease = Self.snapshotters.hold(snapshotter)
                // Owned by the block below, not by the snapshotter (its delegate
                // is weak). Unlike the snapshotter it has no teardown, so being
                // released off the main queue with the block is harmless.
                let timing = SnapshotTiming()
                snapshotter.delegate = timing
                Self.meter.snapshotStarted()
                // The block must not mention `snapshotter` — see above. It ends
                // the lease instead, which drops the last reference on the main
                // queue, one turn after this callback has returned into MapLibre.
                snapshotter.start { snapshot, error in
                    Self.snapshotters.end(lease)
                    guard let snapshot, let cgImage = snapshot.image.cgImage else {
                        timing.finish(succeeded: false)
                        continuation.resume(throwing: error ?? SnapshotError())
                        return
                    }
                    timing.finish(succeeded: true)
                    continuation.resume(returning: (cgImage, snapshot))
                }
            }
        }

        return MapSnapshot(image: image) { lat, lon in
            snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }

    /// **Where every in-flight snapshotter lives until its render resolves** —
    /// on the main queue, and nowhere else.
    ///
    /// MapLibre's snapshotter is bound to the run loop it was created on, and its
    /// `dealloc` joins its render thread. Both halves of that must happen on the
    /// main thread, so the last strong reference has to be dropped there. This
    /// type makes that structural rather than a matter of which queue happens to
    /// release a block: it is the only owner, it is touched only on main
    /// (`dispatchPrecondition`), and `end` defers the release by one turn of the
    /// main queue so the snapshotter is never destroyed from inside its own
    /// completion handler.
    ///
    /// Generic over `AnyObject` so its contract — *the held object is released on
    /// the main thread, whatever thread ends the lease* — can be tested without
    /// running Metal (`MapLibreSubstrateTests`).
    final class MainThreadLeases<Held: AnyObject> {
        struct Lease: Hashable { fileprivate let id: ObjectIdentifier }

        private var held: [ObjectIdentifier: Held] = [:]

        /// Must be called on the main queue, where the object was created.
        func hold(_ object: Held) -> Lease {
            dispatchPrecondition(condition: .onQueue(.main))
            let id = ObjectIdentifier(object)
            held[id] = object
            return Lease(id: id)
        }

        /// Safe from any thread. The release itself always happens on main, on a
        /// later turn of the queue than the caller's.
        func end(_ lease: Lease) {
            DispatchQueue.main.async { [self] in
                held[lease.id] = nil
            }
        }

        /// How many objects are still held — for tests.
        var count: Int {
            dispatchPrecondition(condition: .onQueue(.main))
            return held.count
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
