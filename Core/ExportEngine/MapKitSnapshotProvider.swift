#if canImport(MapKit)
import CoreGraphics
import Foundation
import KamomeTrackingEngine
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

    /// Which of Apple Maps' two appearances to draw the base map in.
    ///
    /// **No default, deliberately** (2026-08-28). Since the film follows the
    /// device's system appearance, an implicit `.light` here is a caller that
    /// silently disagrees with the palette drawn over it — and a golden-frame or
    /// still gate that inherits an appearance nobody stated is a gate whose
    /// verdict moves when someone toggles dark mode. Every construction site says
    /// which base it means, or it does not compile.
    ///
    /// The value is a domain one (`RecapAppearance`), not a UIKit style: the
    /// palette and the base map must be selected by the same value, and this type
    /// runs on platforms UIKit does not.
    public let appearance: RecapAppearance

    public init(displayScale: Int = 1, appearance: RecapAppearance) {
        self.displayScale = displayScale
        self.appearance = appearance
    }

    /// Cannot rotate: this north-up region snapshot is the retiring base map
    /// (handoff §3). The `CameraFrame.bearing` is honestly declared unsupported
    /// (heading-up would mean a rotated `MKMapCamera`) rather than silently
    /// accepted-and-ignored — the follow-cam resolver reads this.
    ///
    /// It *can* render either appearance, so `fixedAppearance` stays nil and the
    /// device's choice reaches the map unchanged.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(
            supportsBearing: false, supportsHeadingUp: false, fixedAppearance: nil,
            maxFramableLongitudeDeg: Self.maxLongitudeSpanDeg
        )
    }

    /// The camera asked for a frame this substrate cannot draw.
    ///
    /// Its own case, separate from both `SnapshotError` and `ScaleError`,
    /// because it is the only one of the three that is **not about what came
    /// back** — nothing was requested. It is the substrate declining, and a
    /// caller can act on it by choosing a different film form.
    public struct UnframableError: Error, CustomStringConvertible {
        public let spanM: Double
        public let centerLat: Double
        public let detail: String

        public var description: String {
            String(
                format: "a %.0f km frame at latitude %.2f cannot be drawn: %@",
                spanM / 1000, centerLat, detail
            )
        }
    }

    /// The widest picture MapKit's snapshotter will draw, in degrees of
    /// longitude. **Measured, not documented** — see `maxFramableLongitudeDeg`.
    ///
    /// ⚠️ Measured at latitude 36.94 only. That it is latitude-independent is
    /// INFERRED from it being a zoom floor (a fixed fraction of the Mercator
    /// world width is a fixed longitude span); the cheapest thing that would
    /// settle it is the same sweep at a second latitude.
    public static let maxLongitudeSpanDeg: Double = 109

    /// The region to ask MapKit for — **or a refusal**.
    ///
    /// This is a guard against a *crash*, not against a bad picture.
    /// `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)` raises
    /// an **Objective-C** exception when the span it computes is larger than the
    /// planet:
    ///
    ///     Invalid Region <center:+36.94, +61.96 span:+254.86, +178.60>
    ///     (NSInvalidArgumentException)
    ///
    /// An ObjC exception is not a Swift error. No `catch` anywhere up the stack
    /// can see it and no `try?` softens it — it terminates the process, taking
    /// the export with it. So the arithmetic is checked here, before MapKit is
    /// handed anything, and answers with a `throw` the caller can actually
    /// handle.
    ///
    /// **A portrait frame reaches this sooner than its width suggests**: the
    /// latitudinal span is `spanM × heightPx/widthPx`, which is 1.778× on 9:16,
    /// so a longitudinal span past ~11,250 km makes the latitudinal one exceed
    /// 180°. Found 2026-09-01 while asking whether a Taiwan→Iceland frame exists.
    public static func region(
        centerLat: Double, centerLon: Double, spanM: Double, widthPx: Int, heightPx: Int
    ) throws -> MKCoordinateRegion {
        let latitudinalM = spanM * Double(heightPx) / Double(widthPx)
        let latitudeDelta = latitudinalM / Geo.metersPerDegreeLatitude
        guard latitudeDelta <= 180 else {
            throw UnframableError(
                spanM: spanM, centerLat: centerLat,
                detail: String(
                    format: "it is %.1f degrees of latitude tall and the planet has 180 "
                        + "(a %d:%d frame is %.3fx taller than it is wide)",
                    latitudeDelta, widthPx, heightPx, Double(heightPx) / Double(widthPx)
                )
            )
        }
        // Longitude degrees at this latitude, by the same equirectangular
        // approximation `Geo.distanceM` uses, so the two agree.
        let metersPerDegreeLon = Geo.metersPerDegreeLatitude * cos(centerLat * .pi / 180)
        let longitudeDelta = metersPerDegreeLon > 0 ? spanM / metersPerDegreeLon : .infinity
        guard longitudeDelta <= maxLongitudeSpanDeg else {
            throw UnframableError(
                spanM: spanM, centerLat: centerLat,
                detail: String(
                    format: "it is %.1f degrees of longitude wide and MapKit draws at most %.0f "
                        + "— past that it returns the same picture however far out it is asked",
                    longitudeDelta, maxLongitudeSpanDeg
                )
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            latitudinalMeters: latitudinalM,
            longitudinalMeters: spanM
        )
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
    ///
    /// **Why `displayScale` is the right factor, and not whatever MapKit rastered
    /// at.** Measured 2026-08-22 (`MapKitSnapshotProbeTests`): `point(for:)`
    /// answers in the *point canvas the snapshotter was given* — a 540x960pt
    /// canvas puts the region's centre at (270, 480) — never in the image's
    /// pixels. `FrameCompositor` then draws that image into the full pixel frame
    /// whatever size it came back at. So a feature travels canvas → frame by
    /// `widthPx / canvasWidth`, which is `displayScale` by construction of
    /// `pointSize`, and the image's own raster scale never enters it.
    public static func pixel(_ point: CGPoint, displayScale: Int) -> CGPoint {
        CGPoint(x: point.x * CGFloat(displayScale), y: point.y * CGFloat(displayScale))
    }

    /// What MapKit actually rastered, as a multiple of the canvas it was handed.
    ///
    /// **It is not always the scale that was requested.** An Iceland film asked
    /// for 2 and got a 1620x2880px image for its 540x960pt canvas — 3x, the
    /// simulator device's own scale. Eighteen probe snapshots across three
    /// scales, three region spans and eight concurrent requests never reproduced
    /// it, so the trigger is unknown and it is treated as something MapKit may
    /// do rather than something Kamome can prevent.
    ///
    /// That deviation is **not** a correctness problem — see `pixel(_:_:)`; the
    /// compositor resamples the larger image into the same frame and the labels
    /// still land at the requested size. What *would* break the projection is a
    /// raster that is not a uniform multiple of the canvas, because then no
    /// single factor maps canvas to frame. That is what this refuses.
    public static func rasterScale(imageWidth: Int, imageHeight: Int, canvas: CGSize) throws -> Double {
        let horizontal = Double(imageWidth) / Double(canvas.width)
        let vertical = Double(imageHeight) / Double(canvas.height)
        // A tenth of a percent: far tighter than any real deviation, loose enough
        // for the rounding a non-integral canvas edge could introduce.
        guard abs(horizontal - vertical) < 0.001, horizontal >= 1 else {
            throw ScaleError(
                widthPx: imageWidth, heightPx: imageHeight, displayScale: 0,
                detail: "MapKit returned \(imageWidth)x\(imageHeight)px for a \(Int(canvas.width))x"
                    + "\(Int(canvas.height))pt canvas — \(horizontal) across and \(vertical) down, "
                    + "so no single factor maps the canvas onto the frame"
            )
        }
        return horizontal
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let size = try Self.pointSize(widthPx: widthPx, heightPx: heightPx, displayScale: displayScale)
        let options = MKMapSnapshotter.Options()
        options.region = try Self.region(
            centerLat: frame.centerLat, centerLon: frame.centerLon,
            spanM: frame.spanM, widthPx: widthPx, heightPx: heightPx
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
        // Checked rather than assumed — this is the one place MapKit's actual
        // rastering is observable. It may legitimately differ from the requested
        // scale (see `rasterScale`); what it may not do is stretch, because the
        // projection below rests on one factor mapping canvas to frame.
        _ = try Self.rasterScale(imageWidth: image.width, imageHeight: image.height, canvas: size)
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
