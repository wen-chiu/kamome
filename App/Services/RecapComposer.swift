import CoreGraphics
import Foundation
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer

/// Maps one trip's records into §4.5 recap inputs (S5). Pure value mapping —
/// photo CGImages arrive pre-loaded (RecapModel owns PhotoKit), and all copy
/// is formatted here so localization never enters KamomeExportEngine.
enum RecapComposer {
    struct Content {
        let route: [CameraPath.Point]
        let stops: [CameraPath.Point]
        let stopCards: [RecapFrameCompositor.StopCard]
        let titleCard: RecapFrameCompositor.TitleCard
        let endCard: RecapFrameCompositor.EndCard
    }

    /// Display-grade recap geometry. Segments matched to the road network
    /// (§4.4, `segment.matched_polyline`) contribute their snapped geometry
    /// at the tighter matched ε — the replay must follow real roads, never
    /// straight lines between GPS points (§4.5 quality bar). Unmatched
    /// segments fall back to raw points at the same ε as S3. Either way the
    /// compositor strokes the traveled path every frame, so everything is
    /// Douglas-Peucker-bounded to protect the §4.5 render budget.
    static func route(
        from segments: [(segment: SegmentRecord, points: [TrackpointRecord])],
        epsilonM: Double,
        matchedEpsilonM: Double
    ) -> [CameraPath.Point] {
        segments.flatMap { item -> [CameraPath.Point] in
            let source: (points: [Simplifier.Point], epsilonM: Double)
            if let encoded = item.segment.matchedPolyline,
               case let decoded = EncodedPolyline.decode(encoded),
               decoded.count >= 2 {
                source = (decoded.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, matchedEpsilonM)
            } else {
                source = (item.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, epsilonM)
            }
            return Simplifier.douglasPeucker(source.points, epsilonM: source.epsilonM)
                .map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        }
    }

    /// `photosByStop` maps stop id → the stop's card photo (highlight first).
    /// Returns nil for trips the phantom guard should have kept out anyway
    /// (no route points).
    static func content(
        trip: TripRecord,
        route: [CameraPath.Point],
        stops: [StopRecord],
        stats: TripStats?,
        photosByStop: [String: CGImage]
    ) -> Content? {
        guard route.count >= 2 else { return nil }

        let stopPoints = stops.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let cards = stops.map { stop in
            RecapFrameCompositor.StopCard(
                name: stop.name ?? String(localized: "stop_unnamed"),
                dayLabel: dayLabel(for: stop.arrivedAt, tripStartedAt: trip.startedAt),
                detail: walkDetail(for: stop),
                photo: photosByStop[stop.id]
            )
        }

        return Content(
            route: route,
            stops: stopPoints,
            stopCards: cards,
            titleCard: RecapFrameCompositor.TitleCard(
                title: trip.title,
                subtitle: titleSubtitle(trip: trip, stats: stats)
            ),
            endCard: RecapFrameCompositor.EndCard(
                statsLines: statsLines(stats: stats, stopCount: stops.count),
                callToAction: String(localized: "recap_get_route"),
                qrCode: RecapQRCode.image(
                    for: shareURLString(tripId: trip.id),
                    sidePx: Int(RecapStyle().qrSidePx)
                )
            )
        )
    }

    /// Same day math as S3's filter chips (TripDetailModel.dayIndex).
    static func dayLabel(for timestamp: Double, tripStartedAt: Double) -> String {
        let day = Int((timestamp - tripStartedAt) / 86_400) + 1
        return String.localizedStringWithFormat(String(localized: "day_chip"), day)
    }

    /// stop.kind hook (ADR 2026-07-18): walk visits carry their walking
    /// duration; dwells (and unknown/legacy kinds) show no detail line.
    static func walkDetail(for stop: StopRecord) -> String? {
        guard StopKind(recordValue: stop.kind) == .walkVisit, let departedAt = stop.departedAt else { return nil }
        let minutes = Int(((departedAt - stop.arrivedAt) / 60).rounded())
        return String.localizedStringWithFormat(String(localized: "recap_walk_detail"), max(minutes, 1))
    }

    static func titleSubtitle(trip: TripRecord, stats: TripStats?) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let start = Date(timeIntervalSince1970: trip.startedAt)
        let end = Date(timeIntervalSince1970: trip.endedAt ?? trip.startedAt)
        let dates = formatter.string(from: start, to: end)
        guard let stats else { return dates }
        return "\(dates) · \(Int((stats.distanceM / 1000).rounded())) km"
    }

    static func statsLines(stats: TripStats?, stopCount: Int) -> [String] {
        guard let stats else { return [] }
        let distanceStops = String.localizedStringWithFormat(
            String(localized: "recap_stat_distance_stops"),
            Int((stats.distanceM / 1000).rounded()),
            stopCount
        )
        let drive = String.localizedStringWithFormat(
            String(localized: "recap_stat_drive"),
            String(format: "%.1f", stats.driveS / 3600)
        )
        return [distanceStops, drive]
    }

    /// P3 placeholder payload: a deep link to this trip. Becomes the real
    /// share URL / `.kamome` file reference when P6/P7 land — the QR is part
    /// of the sharing flow (Chiu, 2026-07-18), so it renders from day one.
    static func shareURLString(tripId: String) -> String {
        "kamome://route/\(tripId)"
    }
}

private extension StopKind {
    /// Readers treat unknown/legacy kinds ("auto", nil) as dwell
    /// (ADR 2026-07-18 stop-kind).
    init?(recordValue: String?) {
        guard let recordValue else { return nil }
        self.init(rawValue: recordValue)
    }
}
