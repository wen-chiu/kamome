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

    public init() {}

    /// Cannot rotate: this north-up region snapshot is the retiring base map
    /// (handoff §3). The `CameraFrame.bearing` is honestly declared unsupported
    /// (heading-up would mean a rotated `MKMapCamera`) rather than silently
    /// accepted-and-ignored — the follow-cam resolver reads this.
    public var capabilities: MapRendererCapabilities {
        MapRendererCapabilities(supportsBearing: false, supportsHeadingUp: false)
    }

    public func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(latitude: frame.centerLat, longitude: frame.centerLon)
        options.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: frame.spanM * Double(heightPx) / Double(widthPx),
            longitudinalMeters: frame.spanM
        )
        options.size = CGSize(width: widthPx, height: heightPx)
        #if canImport(UIKit)
        // 1 point == 1 pixel so frame sizes and point(for:) agree exactly.
        options.traitCollection = UITraitCollection(displayScale: 1)
        #endif

        let snapshot = try await MKMapSnapshotter(options: options).start()
        #if canImport(UIKit)
        guard let image = snapshot.image.cgImage else { throw SnapshotError() }
        #else
        var proposedRect = CGRect(origin: .zero, size: snapshot.image.size)
        guard let image = snapshot.image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { throw SnapshotError() }
        #endif
        return MapSnapshot(image: image) { lat, lon in
            snapshot.point(for: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
}
#endif
