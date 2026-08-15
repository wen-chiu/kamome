#if DEBUG
import Foundation
import KamomePersistence
import KamomeTripComposer

/// Seeds a deterministic demo trip for the Phase 2 gate screenshot
/// (`-demo-seed` launch argument; simulator/debug only).
///
/// Times are anchored to "now" so photos added to the simulator library
/// (`simctl addmedia`, creationDate ≈ import time) fall inside the final
/// stop's interval and flow through the real PhotoKit → matcher → DB path.
enum DemoSeeder {
    private struct DemoStop {
        let index: Int
        let name: String
        let dwellMin: Double
    }

    // Perth → Margaret River day 1, heavily thinned.
    private static let route: [(lat: Double, lon: Double)] = [
        (-31.9530, 115.8570), (-32.1200, 115.8200), (-32.3200, 115.7700),
        (-32.5290, 115.7220), (-32.8000, 115.7000), (-33.0500, 115.6800),
        (-33.3270, 115.6410), (-33.5000, 115.5000), (-33.6440, 115.3450),
        (-33.8000, 115.2000), (-33.9550, 115.0750)
    ]
    private static let stopInfo: [DemoStop] = [
        DemoStop(index: 3, name: "Mandurah", dwellMin: 25),
        DemoStop(index: 6, name: "Bunbury", dwellMin: 25),
        DemoStop(index: 8, name: "Busselton Jetty", dwellMin: 20),
        DemoStop(index: 10, name: "Margaret River", dwellMin: 30)
    ]

    static func seedIfRequested(repository: TripRepository) {
        if ProcessInfo.processInfo.arguments.contains("-demo-seed") {
            seedRecorded(repository: repository)
        }
        if ProcessInfo.processInfo.arguments.contains("-demo-seed-import") {
            seedImported(repository: repository)
        }
    }

    private static func seedRecorded(repository: TripRepository) {
        guard (try? repository.allTrips().isEmpty) == true else { return }

        // Final stop's window straddles "now": library photos land there.
        let end = Date.now.addingTimeInterval(15 * 60).timeIntervalSince1970
        let start = end - 6.5 * 3600
        let dwellTotalS = stopInfo.map(\.dwellMin).reduce(0, +) * 60
        let legStepS = (end - start - dwellTotalS) / Double(route.count - 1)

        var segments: [TripRepository.NewSegment] = []
        var stops: [TripRepository.NewStop] = []
        var previousIndex = 0
        var previousDepart = start
        for stop in stopInfo {
            let points = (previousIndex...stop.index).enumerated().map { offset, routeIndex in
                TripRepository.NewTrackpoint(
                    ts: previousDepart + Double(offset) * legStepS,
                    lat: route[routeIndex].lat,
                    lon: route[routeIndex].lon,
                    speed: 25
                )
            }
            let arrive = points.last?.ts ?? previousDepart
            let depart = min(arrive + stop.dwellMin * 60, end)
            segments.append(.init(
                mode: "drive",
                startedAt: points.first?.ts ?? previousDepart,
                endedAt: arrive,
                points: points
            ))
            stops.append(.init(
                lat: route[stop.index].lat,
                lon: route[stop.index].lon,
                arrivedAt: arrive,
                departedAt: depart
            ))
            previousIndex = stop.index
            previousDepart = depart
        }

        guard let tripId = try? repository.saveCompletedTrip(
            title: "Perth → Margaret River",
            startedAt: start,
            endedAt: end,
            segments: segments,
            stops: stops
        ) else { return }

        decorate(tripId: tripId, driveS: end - start - dwellTotalS, repository: repository)
    }

    /// Seeds a deterministic **imported_photos** trip (`-demo-seed-import`) so
    /// the honest-provenance UI — the S1 "相片重建" badge and the S3 provenance
    /// note (§3) — renders in the real app without a PhotoKit grant (which
    /// simctl cannot pre-answer on iOS 26). Mirrors the shape `ImportService`
    /// writes: one `exif` drive segment carrying the coarse route, stops with
    /// photos attached by construction. Photo refs dangle (asset ids resolve to
    /// nothing) — thumbnails take the graceful-placeholder path; badges/labels
    /// are the point.
    private static func seedImported(repository: TripRepository) {
        guard (try? repository.allTrips().isEmpty) == true else { return }

        let end = Date.now.addingTimeInterval(15 * 60).timeIntervalSince1970
        let start = end - 6.5 * 3600
        let stepS = (end - start) / Double(route.count - 1)

        let points = route.enumerated().map { offset, coord in
            TripRepository.NewTrackpoint(ts: start + Double(offset) * stepS, lat: coord.lat, lon: coord.lon)
        }
        let segment = TripRepository.NewSegment(
            mode: "drive", startedAt: start, endedAt: end,
            points: points, source: SegmentSource.exif.rawValue
        )

        let stopsWithPhotos = stopInfo.enumerated().map { stopOffset, info -> TripRepository.NewStopWithPhotos in
            let arrive = start + Double(info.index) * stepS
            return TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(
                    lat: route[info.index].lat, lon: route[info.index].lon,
                    arrivedAt: arrive, departedAt: arrive + info.dwellMin * 60
                ),
                photos: (0..<2).map { TripRepository.NewPhoto(assetId: "demo-import-\(stopOffset)-\($0)") }
            )
        }

        guard let tripId = try? repository.saveImportedTrip(
            TripRepository.ImportedTrip(
                title: "South West WA (from photos)",
                startedAt: start, endedAt: end,
                source: TripSource.importedPhotos.rawValue,
                segments: [segment], stopsWithPhotos: stopsWithPhotos,
                routeAttachedPhotos: []
            )
        ) else { return }

        if let detail = try? repository.detail(tripId: tripId), detail.stops.count == stopInfo.count {
            for (record, info) in zip(detail.stops, stopInfo) {
                try? repository.setStopName(stopId: record.id, name: info.name)
            }
        }
        let stats = TripStats(distanceM: 271_000, driveS: end - start, walkS: 0, stopCount: stopInfo.count, topSpeedKmh: 96)
        if let json = stats.jsonString() {
            try? repository.updateTripStats(tripId: tripId, statsJson: json)
        }
    }

    /// Stop names, photo refs, and stats — everything S3 shows beyond geometry.
    private static func decorate(tripId: String, driveS: Double, repository: TripRepository) {
        guard let detail = try? repository.detail(tripId: tripId),
              detail.stops.count == stopInfo.count else { return }

        // Names skip the geocoder (deterministic screenshot, no network).
        for (record, info) in zip(detail.stops, stopInfo) {
            try? repository.setStopName(stopId: record.id, name: info.name)
        }

        // Seeded photo refs with dangling asset ids: pins get correct badge
        // counts and thumbnails render the §3 graceful-placeholder path,
        // without needing a photo-library permission grant (simctl privacy
        // cannot pre-answer the iOS 26 photos prompt). Non-empty refs also
        // stop TripDetailModel from re-running the live matcher.
        let busselton = detail.stops[2].id
        let margaretRiver = detail.stops[3].id
        try? repository.replacePhotoRefs(tripId: tripId, with: [
            PhotoRefRecord(id: "demo-ph1", tripId: tripId, stopId: busselton, phAssetId: "demo-missing-1"),
            PhotoRefRecord(id: "demo-ph2", tripId: tripId, stopId: busselton, phAssetId: "demo-missing-2"),
            PhotoRefRecord(
                id: "demo-ph3", tripId: tripId, stopId: margaretRiver,
                phAssetId: "demo-missing-3", isHighlight: 1
            ),
            PhotoRefRecord(id: "demo-ph4", tripId: tripId, stopId: margaretRiver, phAssetId: "demo-missing-4"),
            PhotoRefRecord(id: "demo-ph5", tripId: tripId, stopId: nil, phAssetId: "demo-missing-5")
        ])

        // Stats strip content (~271 km straight-line route, 4 stops).
        let stats = TripStats(
            distanceM: 271_000,
            driveS: driveS,
            walkS: 0,
            stopCount: stopInfo.count,
            topSpeedKmh: 96
        )
        if let json = stats.jsonString() {
            try? repository.updateTripStats(tripId: tripId, statsJson: json)
        }
    }
}
#endif
