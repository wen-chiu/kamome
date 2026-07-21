import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

final class TripRepositoryTests: XCTestCase {
    /// Photo-EXIF import write path (§4.7): cluster synthetic photos, persist as
    /// an `imported_photos` trip, and read it back — proving honest provenance
    /// lands and the trip has the shape RecapComposer/ExportEngine consume.
    func testImportedTripRoundTripsWithHonestProvenance() throws {
        let photos = [
            ImportPhoto(assetId: "a1", timestamp: 0, lat: 63.4040, lon: -19.0410),
            ImportPhoto(assetId: "a2", timestamp: 60, lat: 63.4044, lon: -19.0405),
            ImportPhoto(assetId: "lone", timestamp: 3_600, lat: 63.4500, lon: -18.5000),
            ImportPhoto(assetId: "b1", timestamp: 7_200, lat: 63.5300, lon: -19.5500),
            ImportPhoto(assetId: "b2", timestamp: 7_260, lat: 63.5305, lon: -19.5495)
        ]
        let config = ImportClusteringConfig(stopRadiusM: 2_000, stopSplitGapS: 3_600, minPhotosPerStop: 2)
        let plan = PhotoImportClusterer.plan(photos: photos, config: config)
        XCTAssertEqual(plan.stops.count, 2)          // A, B
        XCTAssertEqual(plan.routeAttachedAssetIds, ["lone"])

        let repository = TripRepository(database: try AppDatabase.inMemory())
        let byId = Dictionary(uniqueKeysWithValues: photos.map { ($0.assetId, $0) })
        func newPhoto(_ id: String) -> TripRepository.NewPhoto {
            let meta = byId[id]!
            return TripRepository.NewPhoto(assetId: id, takenAt: meta.timestamp, lat: meta.lat, lon: meta.lon)
        }
        let segment = TripRepository.NewSegment(
            mode: "drive", startedAt: plan.startedAt, endedAt: plan.endedAt,
            points: plan.routePoints.map {
                TripRepository.NewTrackpoint(ts: $0.timestamp, lat: $0.lat, lon: $0.lon)
            },
            source: SegmentSource.exif.rawValue
        )
        let stopsWithPhotos = plan.stops.map { stop in
            TripRepository.NewStopWithPhotos(
                stop: TripRepository.NewStop(
                    lat: stop.lat, lon: stop.lon,
                    arrivedAt: stop.arrivedAt, departedAt: stop.departedAt
                ),
                photos: stop.photoAssetIds.map(newPhoto)
            )
        }

        let tripId = try repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "Iceland", startedAt: plan.startedAt, endedAt: plan.endedAt,
            source: TripSource.importedPhotos.rawValue,
            segments: [segment], stopsWithPhotos: stopsWithPhotos,
            routeAttachedPhotos: plan.routeAttachedAssetIds.map(newPhoto)
        ))

        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.trip.tripSource, .importedPhotos)
        XCTAssertTrue(detail.trip.tripSource.isReconstructed)
        XCTAssertEqual(detail.segments.count, 1)
        XCTAssertEqual(detail.segments[0].segment.segmentSource, .exif)
        XCTAssertEqual(detail.segments[0].points.count, plan.routePoints.count)
        XCTAssertEqual(detail.stops.count, 2)

        // Every stop photo is attached to a stop; the lone photo is route-attached.
        let attached = detail.photos.filter { $0.stopId != nil }
        let routeAttached = detail.photos.filter { $0.stopId == nil }
        XCTAssertEqual(Set(attached.map(\.phAssetId)), ["a1", "a2", "b1", "b2"])
        XCTAssertEqual(routeAttached.map(\.phAssetId), ["lone"])
    }
    /// End-to-end: replay the Perth fixture through the real engine, persist
    /// the result, and read it back — the exact path End Trip takes.
    func testEngineOutputRoundTripsThroughRepository() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)

        let segments = engine.segments.map { segment in
            TripRepository.NewSegment(
                mode: segment.mode.rawValue,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                points: segment.points.map {
                    TripRepository.NewTrackpoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAcc: $0.hAccM)
                }
            )
        }
        // Mirrors TrackingSession.end(): saved stops are live ∪ derived
        // (ADR 2026-07-18).
        let allStops = engine.stops + StopDeriver.derive(
            segments: engine.segments, engineStops: engine.stops, config: try GPXReplay.loadConfig()
        )
        let stops = allStops.map {
            TripRepository.NewStop(
                lat: $0.lat, lon: $0.lon,
                arrivedAt: $0.arrivedAt, departedAt: $0.departedAt,
                kind: $0.kind.rawValue
            )
        }

        let tripId = try repository.saveCompletedTrip(
            title: "Perth Day 1",
            startedAt: engine.segments.first?.startedAt ?? 0,
            endedAt: engine.stops.last?.departedAt ?? 0,
            segments: segments,
            stops: stops
        )

        XCTAssertEqual(try repository.allTrips().count, 1)
        XCTAssertEqual(try repository.allTrips().first?.status, "completed")
        XCTAssertEqual(try repository.stopCount(tripId: tripId), 4)
        // stop.kind round-trips: perth = 2 live dwells + 2 derived walk visits.
        let persistedKinds = try repository.detail(tripId: tripId)?.stops.map(\.kind) ?? []
        XCTAssertEqual(persistedKinds.filter { $0 == "dwell" }.count, 2)
        XCTAssertEqual(persistedKinds.filter { $0 == "walk_visit" }.count, 2)
        XCTAssertEqual(try repository.segmentCount(tripId: tripId), engine.segments.count)
        let pointTotal = engine.segments.reduce(0) { $0 + $1.points.count }
        XCTAssertEqual(try repository.trackpointCount(tripId: tripId), pointTotal)
    }

    func testStopEditingAndPhotoOperations() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Edit fixture",
            startedAt: 0,
            endedAt: 10_000,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: 0, endedAt: 1_000, points: [
                    TripRepository.NewTrackpoint(ts: 0, lat: -31.95, lon: 115.86),
                    TripRepository.NewTrackpoint(ts: 1_000, lat: -32.00, lon: 115.87)
                ])
            ],
            stops: [
                TripRepository.NewStop(lat: -32.0, lon: 115.87, arrivedAt: 1_000, departedAt: 2_000),
                TripRepository.NewStop(lat: -32.5, lon: 115.72, arrivedAt: 3_000, departedAt: 4_000)
            ]
        )
        var detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        let firstStop = detail.stops[0]
        let secondStop = detail.stops[1]

        // Rename + note (S4).
        try repository.setStopName(stopId: firstStop.id, name: "咖啡店")
        try repository.setStopNote(stopId: firstStop.id, note: "flat white")
        detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops[0].name, "咖啡店")
        XCTAssertEqual(detail.stops[0].note, "flat white")

        // Photos attach to stops; deleting a stop detaches, not deletes.
        try repository.replacePhotoRefs(tripId: tripId, with: [
            PhotoRefRecord(id: "ph1", tripId: tripId, stopId: firstStop.id, phAssetId: "asset-1"),
            PhotoRefRecord(id: "ph2", tripId: tripId, stopId: secondStop.id, phAssetId: "asset-2")
        ])
        try repository.setPhotoHighlight(photoId: "ph1", isHighlight: true)
        try repository.deleteStop(stopId: secondStop.id)
        detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, 1)
        XCTAssertEqual(detail.photos.count, 2, "deleting a stop must not delete its photos")
        XCTAssertNil(detail.photos.first { $0.id == "ph2" }?.stopId)
        XCTAssertEqual(detail.photos.first { $0.id == "ph1" }?.isHighlight, 1)
    }

    func testMergeStops() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Merge fixture", startedAt: 0, endedAt: 10_000, segments: [],
            stops: [
                TripRepository.NewStop(lat: -32.0, lon: 115.87, arrivedAt: 1_000, departedAt: 2_000),
                TripRepository.NewStop(lat: -32.0005, lon: 115.8705, arrivedAt: 2_100, departedAt: 3_000)
            ]
        )
        var detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        try repository.replacePhotoRefs(tripId: tripId, with: [
            PhotoRefRecord(id: "ph1", tripId: tripId, stopId: detail.stops[1].id, phAssetId: "asset-1")
        ])

        try repository.mergeStops(keptId: detail.stops[0].id, absorbedId: detail.stops[1].id)
        detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.stops.count, 1)
        XCTAssertEqual(detail.stops[0].arrivedAt, 1_000)
        XCTAssertEqual(detail.stops[0].departedAt, 3_000)
        XCTAssertEqual(detail.photos.first?.stopId, detail.stops[0].id, "photos follow the merge")
    }

    /// Debug export path: a snapshot is a complete standalone database that
    /// opens on its own and contains the saved trip.
    func testSnapshotDatabaseProducesOpenableCopy() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        _ = try repository.saveCompletedTrip(
            title: "Snapshot fixture", startedAt: 0, endedAt: 1_000,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: 0, endedAt: 1_000, points: [
                    TripRepository.NewTrackpoint(ts: 0, lat: -31.95, lon: 115.86)
                ])
            ],
            stops: []
        )

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-snapshot-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try repository.snapshotDatabase(to: path)

        let copy = TripRepository(database: try AppDatabase.onDisk(path: path))
        XCTAssertEqual(try copy.allTrips().count, 1)
        XCTAssertEqual(try copy.allTrips().first?.title, "Snapshot fixture")
    }
}
