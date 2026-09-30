import Foundation
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer

/// The day chips' arithmetic, what each day shows, and the lines it draws. Its
/// own file because the model's body is held to 250 lines under SwiftLint.
extension TripDetailModel {
    /// What days are counted by: each stop's own zone (`TripClock`, arch review
    /// 2026-09-26), so chip N is the Nth local date of the trip — the same count
    /// the film's HUD and end card draw.
    var clock: TripClock {
        TripClock(stops: detail?.stops ?? [])
    }

    /// Calendar days (Chiu 2026-09-25): chip N is the trip's Nth date.
    var dayCount: Int {
        guard let detail, let endedAt = detail.trip.endedAt else { return 1 }
        return clock.dayCount(startedAt: detail.trip.startedAt, endedAt: endedAt)
    }

    /// The date chip `day` (0-based) stands for.
    func date(ofDay day: Int) -> Date? {
        guard let detail else { return nil }
        return clock.date(ofDay: day, tripStartedAt: detail.trip.startedAt)
    }

    func dayIndex(of timestamp: Double) -> Int {
        guard let detail else { return 0 }
        return clock.dayIndex(of: timestamp, tripStartedAt: detail.trip.startedAt)
    }

    var visibleStops: [StopRecord] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.stops }
        return detail.stops.filter { dayIndex(of: $0.arrivedAt) == selectedDay }
    }

    var visibleSegments: [(segment: SegmentRecord, points: [TrackpointRecord])] {
        guard let detail else { return [] }
        guard let selectedDay else { return detail.segments }
        return detail.segments.filter { dayIndex(of: $0.segment.startedAt) == selectedDay }
    }

    /// The segment's line as `refresh()` thinned it; empty until the first read.
    func displayPolyline(for segment: SegmentRecord) -> [Simplifier.Point] {
        displayPolylines[segment.id] ?? []
    }

    /// Douglas-Peucker per segment, keyed by segment id. Pure, so `refresh()`
    /// runs it off the main thread beside the read.
    static func thinned(
        _ segments: [(segment: SegmentRecord, points: [TrackpointRecord])], epsilonM: Double
    ) -> [String: [Simplifier.Point]] {
        Dictionary(uniqueKeysWithValues: segments.map { item in
            (item.segment.id, Simplifier.douglasPeucker(
                item.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }, epsilonM: epsilonM
            ))
        })
    }
}
