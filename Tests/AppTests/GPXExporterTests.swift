@testable import Kamome
import KamomePersistence
import XCTest

/// The debug GPX export must produce fixture-shaped output (one <trk> per
/// segment, <ele>/<time> per point, <wpt> per stop) so a real drive can be
/// dropped into Tests/Fixtures and replayed.
final class GPXExporterTests: XCTestCase {
    func testExportedTripMatchesFixtureShape() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try repository.saveCompletedTrip(
            title: "Coffee & Coast",
            startedAt: 1_000, endedAt: 5_000,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: 1_000, endedAt: 3_000, points: [
                    TripRepository.NewTrackpoint(ts: 1_000, lat: -31.95, lon: 115.86, altitude: 30),
                    TripRepository.NewTrackpoint(ts: 1_005, lat: -31.96, lon: 115.85, altitude: 31)
                ]),
                TripRepository.NewSegment(mode: "walk", startedAt: 3_000, endedAt: 5_000, points: [
                    TripRepository.NewTrackpoint(ts: 3_000, lat: -31.97, lon: 115.84)
                ])
            ],
            stops: [
                TripRepository.NewStop(lat: -31.96, lon: 115.85, arrivedAt: 2_000, departedAt: 2_500)
            ]
        )
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))

        let gpx = GPXExporter.gpx(for: detail)

        XCTAssertTrue(gpx.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(gpx.contains("<name>Coffee &amp; Coast</name>"), "title is XML-escaped")
        XCTAssertEqual(gpx.components(separatedBy: "<trk>").count - 1, 2, "one trk per segment")
        XCTAssertTrue(gpx.contains("<trk><name>drive</name><trkseg>"))
        XCTAssertTrue(gpx.contains("<trkpt lat=\"-31.95\" lon=\"115.86\"><ele>30.0</ele>"))
        XCTAssertTrue(gpx.contains("<time>1970-01-01T00:16:40Z</time>"), "epoch 1000 as ISO8601 UTC")
        XCTAssertEqual(gpx.components(separatedBy: "<wpt ").count - 1, 1, "one wpt per stop")
        XCTAssertTrue(gpx.contains("</gpx>"))
        XCTAssertFalse(gpx.contains("<ele></ele>"), "nil altitude omits ele instead of emitting it empty")
    }
}
