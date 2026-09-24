import Foundation
import KamomeConfig
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer

/// Merges several trips into one, so a journey recorded day by day, or partly
/// recorded and partly rebuilt from photographs, becomes one film
/// (ADR 2026-09-24 (b), Chiu's three calls):
///
/// 1. **A recording may merge with a photo reconstruction.** Provenance stays
///    per segment, so the film still draws each leg as what it is. The merged
///    trip as a whole is labelled reconstructed if any part is: a partly
///    recorded trip shown as "from photos" understates, and the reverse would
///    claim a recording that did not happen (rule 5).
/// 2. **The gap between two parts is drawn like an imported leg.** Parts that
///    ended and began far apart are joined by a `mergeGap` leg of two points.
///    It is routed like a photo leg and drawn dashed when no road comes back,
///    never as a recording. Parts that ended and began in one place get an
///    overnight stop there instead.
/// 3. **Films of the parts are kept** on the merged trip.
///
/// Parts whose times overlap are refused. Two records of the same hours would
/// draw the same road twice.
enum TripMerger {
    enum Refusal: Error, Equatable {
        case tooFew
        case notCompleted
        case overlapping
        case missing
    }

    /// Decides the merge. Pure: no database, no clock, no photo library.
    static func plan(
        parts: [TripRepository.TripDetail],
        config: TrackingConfig
    ) throws -> TripRepository.TripMerge {
        guard parts.count >= 2 else { throw Refusal.tooFew }
        guard parts.allSatisfy({ $0.trip.endedAt != nil }) else { throw Refusal.notCompleted }
        let ordered = parts.sorted { $0.trip.startedAt < $1.trip.startedAt }
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            guard let earlierEnd = earlier.trip.endedAt, earlierEnd <= later.trip.startedAt else {
                throw Refusal.overlapping
            }
        }

        var gapSegments: [TripRepository.NewSegment] = []
        var junctionStops: [TripRepository.NewStop] = []
        var stopDepartures: [(stopId: String, departedAt: Double)] = []
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            guard let end = lastFix(of: earlier), let start = firstFix(of: later) else { continue }
            let apart = Geo.distanceM(latA: end.lat, lonA: end.lon, latB: start.lat, lonB: start.lon)
            if apart >= config.trip.mergeGapMinM {
                gapSegments.append(TripRepository.NewSegment(
                    mode: gapMode(before: earlier, after: later),
                    startedAt: end.ts,
                    endedAt: start.ts,
                    points: [
                        TripRepository.NewTrackpoint(ts: end.ts, lat: end.lat, lon: end.lon),
                        TripRepository.NewTrackpoint(ts: start.ts, lat: start.lat, lon: start.lon)
                    ],
                    source: SegmentSource.mergeGap.rawValue
                ))
            } else if let stop = endingStop(of: earlier, at: end, radiusM: config.dwell.regionRadiusM) {
                stopDepartures.append((stop.id, start.ts))
            } else {
                junctionStops.append(TripRepository.NewStop(
                    lat: end.lat, lon: end.lon, arrivedAt: end.ts, departedAt: start.ts,
                    kind: StopKind.dwell.rawValue
                ))
            }
        }

        let kept = ordered[0]
        let reconstructed = ordered.contains { $0.trip.tripSource.isReconstructed }
        return TripRepository.TripMerge(
            keptId: kept.trip.id,
            absorbedIds: ordered.dropFirst().map(\.trip.id),
            startedAt: kept.trip.startedAt,
            endedAt: ordered.compactMap(\.trip.endedAt).max() ?? kept.trip.startedAt,
            source: reconstructed ? TripSource.importedPhotos.rawValue : TripSource.recorded.rawValue,
            statsJson: reconstructed ? nil : summedStats(
                ordered, stopCount: ordered.reduce(0) { $0 + $1.stops.count } + junctionStops.count
            )?.jsonString(),
            discoveryKey: ordered.lazy.compactMap(\.trip.discoveryKey).first,
            gapSegments: gapSegments,
            junctionStops: junctionStops,
            stopDepartures: stopDepartures
        )
    }

    /// Merges the trips and returns the survivor's id.
    ///
    /// A recorded part is matched to its photographs first if it never was.
    /// Recorded trips match photos lazily, the first time Trip Detail opens,
    /// and only when the trip has none. Once one part brings photos, that
    /// check would never fire again for the days the others covered.
    @MainActor
    static func merge(
        tripIds: [String],
        repository: TripRepository,
        config: TrackingConfig,
        photoService: PhotoLibraryService
    ) async throws -> String {
        let parts = try tripIds.map { id -> TripRepository.TripDetail in
            guard let detail = try repository.detail(tripId: id) else { throw Refusal.missing }
            return detail
        }
        let merge = try plan(parts: parts, config: config)

        for part in parts where part.photos.isEmpty && !part.trip.tripSource.isReconstructed {
            guard let endedAt = part.trip.endedAt else { continue }
            await withCheckedContinuation { continuation in
                photoService.matchPhotos(
                    tripId: part.trip.id, startedAt: part.trip.startedAt, endedAt: endedAt, stops: part.stops
                ) { _ in continuation.resume() }
            }
        }

        try repository.applyMerge(merge)
        KamomeLog.recording.notice("""
            merge: \(parts.count, privacy: .public) trips, \(merge.gapSegments.count, privacy: .public) gap legs, \
            \(merge.junctionStops.count + merge.stopDepartures.count, privacy: .public) overnight stops
            """)
        // Gap legs are routed like photo legs; the recap path joins this run.
        let matcher = RouteMatchService(repository: repository, matching: config.matching)
        RouteMatchCoordinator.shared.start(tripId: merge.keptId, service: matcher)
        return merge.keptId
    }

    // MARK: - Junctions

    private struct Fix {
        let ts: Double
        let lat: Double
        let lon: Double
    }

    /// Where a part really ended: its latest point, or its latest stop when it
    /// has no points (a reconstruction can be a single stop).
    private static func lastFix(of part: TripRepository.TripDetail) -> Fix? {
        let point = part.segments.flatMap(\.points).max { $0.ts < $1.ts }
        let stop = part.stops.max { ($0.departedAt ?? $0.arrivedAt) < ($1.departedAt ?? $1.arrivedAt) }
        switch (point, stop) {
        case let (point?, stop?) where (stop.departedAt ?? stop.arrivedAt) > point.ts:
            return Fix(ts: stop.departedAt ?? stop.arrivedAt, lat: stop.lat, lon: stop.lon)
        case let (point?, _):
            return Fix(ts: point.ts, lat: point.lat, lon: point.lon)
        case let (nil, stop?):
            return Fix(ts: stop.departedAt ?? stop.arrivedAt, lat: stop.lat, lon: stop.lon)
        case (nil, nil):
            return nil
        }
    }

    private static func firstFix(of part: TripRepository.TripDetail) -> Fix? {
        let point = part.segments.flatMap(\.points).min { $0.ts < $1.ts }
        let stop = part.stops.min { $0.arrivedAt < $1.arrivedAt }
        switch (point, stop) {
        case let (point?, stop?) where stop.arrivedAt < point.ts:
            return Fix(ts: stop.arrivedAt, lat: stop.lat, lon: stop.lon)
        case let (point?, _):
            return Fix(ts: point.ts, lat: point.lat, lon: point.lon)
        case let (nil, stop?):
            return Fix(ts: stop.arrivedAt, lat: stop.lat, lon: stop.lon)
        case (nil, nil):
            return nil
        }
    }

    /// The stop a part ended at, which then stretches over the night instead of
    /// a second stop appearing beside it.
    private static func endingStop(
        of part: TripRepository.TripDetail, at end: Fix, radiusM: Double
    ) -> StopRecord? {
        guard let last = part.stops.max(by: { $0.arrivedAt < $1.arrivedAt }),
              (last.departedAt ?? .infinity) >= end.ts,
              Geo.distanceM(latA: last.lat, lonA: last.lon, latB: end.lat, lonB: end.lon) <= radiusM
        else { return nil }
        return last
    }

    /// The gap is the vehicle's journey, not the walk to the hotel door: the
    /// mode of the nearest non-walking leg on either side, else drive.
    private static func gapMode(before: TripRepository.TripDetail, after: TripRepository.TripDetail) -> String {
        let travelling: (SegmentRecord) -> Bool = {
            let mode = TransportMode(rawValue: $0.mode)
            return mode != .walk && mode != .unknown && mode != nil
        }
        return before.segments.map(\.segment).last(where: travelling)?.mode
            ?? after.segments.map(\.segment).first(where: travelling)?.mode
            ?? TransportMode.drive.rawValue
    }

    /// Recorded parts only: measured totals add up, the top speed is the top.
    /// nil if any part never stored its stats.
    private static func summedStats(_ parts: [TripRepository.TripDetail], stopCount: Int) -> TripStats? {
        let stats = parts.compactMap { TripStats.from(jsonString: $0.trip.statsJson) }
        guard stats.count == parts.count else { return nil }
        return TripStats(
            distanceM: stats.reduce(0) { $0 + $1.distanceM },
            driveS: stats.reduce(0) { $0 + $1.driveS },
            walkS: stats.reduce(0) { $0 + $1.walkS },
            stopCount: stopCount,
            topSpeedKmh: stats.map(\.topSpeedKmh).max() ?? 0
        )
    }
}
