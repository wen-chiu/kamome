import KamomeConfig
import KamomeExportEngine
import KamomeTripComposer
import MapKit

/// **What Trip Detail's map frames: the trip itself** (Chiu 2026-10-26, #295
/// item 5) — every line it draws and every stop it pins, spanned by
/// `trip_map.frame_padding`, and nothing around them. MapKit's automatic camera
/// added margins of its own: the sample's coast road sat in a map that was
/// mostly the island's west.
///
/// **Equatable on purpose.** The map re-frames only when this changes — the
/// first read, a day chip, a road that lands — never on a reload that draws the
/// same thing (each stop that gets its name is one), which would undo a pan.
struct TripMapFrame: Equatable {
    let centerLat: Double
    let centerLon: Double
    let latSpan: Double
    let lonSpan: Double

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// nil when there is nothing to frame.
    init?(points: [Simplifier.Point], config: TrackingConfig.TripMap) {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.lat)
        let lons = Self.unwrapped(points.map(\.lon))
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return nil }
        centerLat = (south + north) / 2
        centerLon = Antimeridian.normalized((west + east) / 2)
        let narrowest = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            latitudinalMeters: config.frameMinSpanM, longitudinalMeters: config.frameMinSpanM
        ).span
        // The whole globe is as wide as a frame can be.
        latSpan = min(max((north - south) * config.framePadding, narrowest.latitudeDelta), 180)
        lonSpan = min(max((east - west) * config.framePadding, narrowest.longitudeDelta), 360)
    }

    /// Longitudes made continuous across ±180° by the film's rule (ADR
    /// 2026-10-07, `Antimeridian.windowStart`, internal to ExportEngine): the
    /// seam goes into the widest stretch of longitude the trip never visits, so
    /// a trip astride 180° is framed across it and not round the planet. A trip
    /// that does not cross it comes back unchanged.
    static func unwrapped(_ longitudes: [Double]) -> [Double] {
        let sorted = longitudes.sorted()
        guard let first = sorted.first, let last = sorted.last else { return longitudes }
        var widest = first + 360 - last
        var start: Double?
        for (west, east) in zip(sorted, sorted.dropFirst()) where east - west > widest {
            widest = east - west
            start = east
        }
        guard let start else { return longitudes }
        return longitudes.map { $0 < start ? $0 + 360 : $0 }
    }
}
