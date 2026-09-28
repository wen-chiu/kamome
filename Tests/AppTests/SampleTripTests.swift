@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// Kamome's sample trip (ADR 2026-09-28-sample-trip): what ships, what it
/// writes, and that nothing mistakes it for the person's own journey.
@MainActor
final class SampleTripTests: XCTestCase {
    private func repository() throws -> TripRepository {
        TripRepository(database: try AppDatabase.inMemory())
    }

    // MARK: - What ships

    func testTheManifestShipsFiveStopsJoinedByFourRoads() throws {
        let manifest = try SampleTrip.manifest()
        XCTAssertEqual(manifest.stops.count, 5)
        XCTAssertEqual(manifest.legs.count, manifest.stops.count - 1, "one road between each pair of stops")
        for stop in manifest.stops {
            XCTAssertNotNil(stop.names["en"], "\(stop.id) needs an English name")
            XCTAssertNotNil(stop.names["zh-Hant"], "\(stop.id) needs a Chinese name")
            XCTAssertFalse(stop.photos.isEmpty, "\(stop.id) has no drawing — its card would be blank")
        }
    }

    func testEveryDrawingTheManifestNamesIsInTheApp() throws {
        for stop in try SampleTrip.manifest().stops {
            for name in stop.photos {
                XCTAssertNotNil(
                    SampleTrip.image(assetId: SampleTrip.assetPrefix + name),
                    "sample-\(name).png is missing from the app bundle"
                )
            }
        }
    }

    /// Each road starts where its stop is and ends where the next one is. The
    /// router snaps to the nearest road, so an island stop (Sanxiantai, across
    /// its footbridge) sits a few hundred metres off — never kilometres.
    func testEachRoadRunsFromItsStopToTheNext() throws {
        let manifest = try SampleTrip.manifest()
        let toleranceM = 1_000.0
        for (index, leg) in manifest.legs.enumerated() {
            let points = EncodedPolyline.decode(leg.polyline)
            let first = try XCTUnwrap(points.first), last = try XCTUnwrap(points.last)
            XCTAssertGreaterThan(points.count, 2, "leg \(index) is a straight line, not a road")
            let from = manifest.stops[index], to = manifest.stops[index + 1]
            XCTAssertLessThan(Geo.distanceM(latA: first.lat, lonA: first.lon, latB: from.lat, lonB: from.lon), toleranceM)
            XCTAssertLessThan(Geo.distanceM(latA: last.lat, lonA: last.lon, latB: to.lat, lonB: to.lon), toleranceM)
        }
    }

    // MARK: - What it writes

    func testTheSampleIsWrittenAsASampleWithItsRoadsAlreadyKnown() throws {
        let repository = try repository()
        let manifest = try SampleTrip.manifest()
        // Not the default car, so the assertion proves the write.
        let tripId = try SampleTrip.create(repository: repository, vehicleId: "scooter", localizations: ["en"])
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))

        XCTAssertEqual(detail.trip.tripSource, .sample)
        XCTAssertEqual(detail.trip.title, manifest.titles["en"])
        XCTAssertEqual(detail.trip.vehicleId, "scooter")

        let segments = detail.segments.map(\.segment).sorted { $0.startedAt < $1.startedAt }
        XCTAssertEqual(segments.map(\.polylineOrEmpty), manifest.legs.map(\.polyline),
                       "the stored road is the shipped one, so routing never asks")
        XCTAssertTrue(segments.allSatisfy { $0.segmentSource == .sample })
        XCTAssertTrue(segments.allSatisfy { $0.routeVerdict == .road })

        let stops = detail.stops.sorted { $0.arrivedAt < $1.arrivedAt }
        XCTAssertEqual(stops.map(\.name), manifest.stops.map { $0.names["en"] }, "named from the manifest, never geocoded")
        XCTAssertTrue(detail.photos.allSatisfy { SampleTrip.isSampleAsset($0.phAssetId) })
        XCTAssertEqual(detail.photos.count, manifest.stops.reduce(0) { $0 + $1.photos.count })
    }

    func testChineseIsUsedWhenTheAppShowsChinese() throws {
        let repository = try repository()
        let tripId = try SampleTrip.create(repository: repository, vehicleId: "car-red", localizations: ["zh-Hant"])
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        XCTAssertEqual(detail.trip.title, "範例・花蓮到台東")
        XCTAssertTrue(detail.stops.contains { $0.name == "三仙台" })
    }

    func testTheSampleDaysAreTaipeiTimes() throws {
        // 08:30 in Taipei (UTC+8) is 00:30 UTC.
        let epoch = try SampleTrip.epoch("2025-11-15", "08:30", "Asia/Taipei")
        XCTAssertEqual(epoch, 1_763_166_600)
    }

    // MARK: - The film reads its drawings

    func testTheFilmResolvesASampleDrawingWithoutThePhotoLibrary() async throws {
        let resolver = PhotoLibraryPhotoResolver()
        let ref = PhotoRef.asset(SampleTrip.assetPrefix + "sanxiantai-1")
        let summary = await resolver.warm([ref], targetPx: 600, timeoutS: 1)
        XCTAssertEqual(summary.resolved, 1)
        XCTAssertNotNil(resolver.image(for: ref, targetPx: 600))
    }

    func testAnOrdinaryAssetIdIsNeverTakenForASampleDrawing() {
        XCTAssertNil(SampleTrip.imageURL(assetId: "9F983DBA-EC35-42B8-8773-B597CF782EDD/L0/001"))
        XCTAssertFalse(SampleTrip.isSampleAsset("sanxiantai-1"))
    }

    // MARK: - Nothing mistakes it for the person's trip

    func testTripDetailCallsItASampleNeverAReconstruction() throws {
        let repository = try repository()
        let tripId = try SampleTrip.create(repository: repository, vehicleId: "car-red")
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)
        model.reload()

        XCTAssertTrue(model.isSample)
        XCTAssertFalse(model.isReconstructed, "\"from your photos\" would be a false claim about the sample")
        XCTAssertFalse(model.photoAccessIsLimited, "the sample offers no library to grow")
        XCTAssertTrue(TripSource.sample.isReconstructed, "still not a recording — nothing may treat it as proof")
    }
}

private extension SegmentRecord {
    var polylineOrEmpty: String { matchedPolyline ?? "" }
}
