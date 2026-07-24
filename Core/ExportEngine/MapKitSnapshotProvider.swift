#if canImport(MapKit)
import CoreGraphics
import Foundation
import MapKit

/// Shipping base-map source (§4.5 step 2): one MKMapSnapshotter render per
/// keyframe. The returned projection wraps `snapshot.point(for:)`, so overlay
/// drawing aligns with MapKit's actual tile layout — never reimplement the
/// mercator math on top of it.
public struct MapKitSnapshotProvider: RecapSnapshotProviding {
    public struct SnapshotError: Error {}

    public init() {}

    /// `bearing` is accepted for protocol conformance but ignored: this
    /// north-up region snapshot is the retiring base map (handoff §3), and the
    /// camera path only emits a non-zero bearing under `follow_heading_up`,
    /// which requires the MapLibre substrate. Heading-up on MapKit would mean
    /// switching to a rotated `MKMapCamera`, which isn't worth it here.
    public func snapshot(
        centerLat: Double,
        centerLon: Double,
        spanM: Double,
        bearing: Double,
        widthPx: Int,
        heightPx: Int
    ) async throws -> MapSnapshot {
        let options = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        options.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: spanM * Double(heightPx) / Double(widthPx),
            longitudinalMeters: spanM
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
