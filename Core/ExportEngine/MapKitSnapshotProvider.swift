#if canImport(MapKit)
import CoreGraphics
import Foundation
import MapKit

/// Shipping base-map source (§4.5 step 2): one MKMapSnapshotter render per
/// keyframe. The returned projection wraps `snapshot.point(for:)`, so overlay
/// drawing aligns with MapKit's actual tile layout — never reimplement the
/// mercator math on top of it.
public struct MapKitSnapshotProvider: MapRenderer {
    public struct SnapshotError: Error {}

    /// The snapshot came back at a size nobody can project through.
    ///
    /// Its own case rather than `SnapshotError` because the two mean opposite
    /// things: `SnapshotError` is "MapKit gave us nothing", this is "MapKit gave
    /// us something whose geometry does not match what was asked for", which
    /// would otherwise be invisible — a projection off by a constant looks
    /// plausible in a still frame and drifts in motion.
    public struct ScaleError: Error, CustomStringConvertible {
        public let widthPx: Int
        public let heightPx: Int
        public let displayScale: Int
        public let detail: String

        public var description: String {
            "\(widthPx)x\(heightPx)px at displayScale \(displayScale): \(detail)"
        }
    }

    /// Which of Apple Maps' two appearances the base map draws in.
    ///
    /// A look decision, not a rendering detail: the souvenir-map direction has
    /// been dark since `Docs/decisions.md` 2026-07-22, and the film's grade and
    /// vignette sit over whatever comes back. Named here rather than taken as a
    /// `UIUserInterfaceStyle` so the type's public surface stays free of UIKit —
    /// MapKit exists on platforms UIKit does not.
    public enum Appearance {
        case light
        case dark
    }

    /// Points per pixel in the snapshot MapKit is asked for.
    ///
    /// **1 is not a tuning choice — it is what every caller got before this
    /// parameter existed**, and it stays the default so the shipping path is
    /// unchanged until Chiu judges a render. Raising it is the only lever on
    /// **place-label size**: MapKit draws labels at fixed *point* sizes, so at
    /// scale 2 the same canvas is half as many points across and its labels come
    /// back twice as large in pixels, with the pixel output identical.
    ///
    /// An `Int` rather than a `CGFloat` because it must divide the frame exactly
    /// (see `pointSize`), and MapKit's own scales are whole numbers anyway.
    public let displayScale: Int
    public let appearance: Appearance

    public init(displayScale: Int = 1, appearance: Appearance = .light) {
        self.displayScale = displayScale
        self.appearance = appearance
    }

    /// Cannot rotate: this north-up region snapshot is the retiring base map
    /// (handoff §3). The `CameraFrame.bearing` is honestly declared unsupported
    /// (heading-up would mean a rotated `MKMapCamera`) rather than silently
    /// accepted-and-ignored — the follow-cam resolver reads this.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(supportsBearing: false, supportsHeadingUp: false)
    }

    // MARK: - The points/pixels seam
    //
    // `MKMapSnapshotterOptions.size` is in POINTS, the image comes back at
    // `size × displayScale` PIXELS, and `snapshot.point(for:)` answers in
    // POINTS. `MapSnapshot`'s contract is pixels — `RenderSurface.cgPoint` flips
    // a projected point against `heightPx`, and `FrameCompositor` draws the
    // image into the pixel frame. At displayScale 1 the two spaces coincide,
    // which is why the original comment said "1 point == 1 pixel so frame sizes
    // and point(for:) agree exactly". Above 1 they must be reconciled, and both
    // halves of that live here as arithmetic a test can reach without taking a
    // snapshot.

    /// The canvas to ask MapKit for, in points, so the image lands at exactly
    /// `widthPx × heightPx`.
    ///
    /// Throws rather than rounding. A canvas of 154.28 points at scale 7 comes
    /// back as some rounded pixel size that is *near* the frame, and near is the
    /// failure this whole seam exists to prevent: every overlay would sit a
    /// fraction of a percent off the road it names, everywhere, consistently
    /// enough to look deliberate.
    public static func pointSize(widthPx: Int, heightPx: Int, displayScale: Int) throws -> CGSize {
        guard displayScale >= 1 else {
            throw ScaleError(
                widthPx: widthPx, heightPx: heightPx, displayScale: displayScale,
                detail: "display scale must be at least 1"
            )
        }
        guard widthPx % displayScale == 0, heightPx % displayScale == 0 else {
            throw ScaleError(
                widthPx: widthPx, heightPx: heightPx, displayScale: displayScale,
                detail: "the frame is not a whole number of points at this scale"
            )
        }
        return CGSize(width: widthPx / displayScale, height: heightPx / displayScale)
    }

    /// A `point(for:)` answer moved into the pixel space `MapSnapshot` promises.
    ///
    /// The whole correction is this multiply. It is a named function because the
    /// bug it prevents is a missing one, and a missing multiply inside a closure
    /// is not something any existing gate can see: the golden-frame gates render
    /// on `FlatSnapshotProvider` and the continuity gate never renders at all.
    public static func pixel(_ point: CGPoint, displayScale: Int) -> CGPoint {
        CGPoint(x: point.x * CGFloat(displayScale), y: point.y * CGFloat(displayScale))
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let size = try Self.pointSize(widthPx: widthPx, heightPx: heightPx, displayScale: displayScale)
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(latitude: frame.centerLat, longitude: frame.centerLon)
        options.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: frame.spanM * Double(heightPx) / Double(widthPx),
            longitudinalMeters: frame.spanM
        )
        options.size = size
        #if canImport(UIKit)
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(displayScale: CGFloat(displayScale)),
            UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
        ])
        #endif

        let snapshot = try await MKMapSnapshotter(options: options).start()
        #if canImport(UIKit)
        guard let image = snapshot.image.cgImage else { throw SnapshotError() }
        #else
        var proposedRect = CGRect(origin: .zero, size: snapshot.image.size)
        guard let image = snapshot.image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { throw SnapshotError() }
        #endif
        // The projection is corrected by `displayScale`, so the image had better
        // actually be at `displayScale`. Checked rather than assumed: this is the
        // one place the assumption is observable, and a platform that ignores the
        // trait collection would otherwise hand back a silently wrong film.
        guard image.width == widthPx, image.height == heightPx else {
            throw ScaleError(
                widthPx: widthPx, heightPx: heightPx, displayScale: displayScale,
                detail: "MapKit returned \(image.width)x\(image.height)px for a \(Int(size.width))x"
                    + "\(Int(size.height))pt canvas — it did not honour the requested scale"
            )
        }
        let scale = displayScale
        return MapSnapshot(image: image) { lat, lon in
            Self.pixel(
                snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon)),
                displayScale: scale
            )
        }
    }
}
#endif
