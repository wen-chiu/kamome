@testable import Kamome
import KamomeConfig
import KamomePersistence
import XCTest

/// **Trip Detail's read is off the main thread** (#128). `repository.detail`
/// carries every trackpoint; a two-week recording is ~200 000 of them
/// (`Docs/handoff-long-recording.md`), and the read ran inside `reload()` on
/// the main thread, once per appearance, rename, export outcome and geocoded
/// stop.
@MainActor
final class TripDetailReloadTests: XCTestCase {
    private func longTrip(points: Int) throws -> (TripRepository, String) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let start = 1_787_382_000.0
        let track = (0 ..< points).map {
            TripRepository.NewTrackpoint(ts: start + Double($0), lat: 35.0 + Double($0) * 1e-5, lon: 139.0)
        }
        let end = start + Double(points)
        let tripId = try repository.saveCompletedTrip(
            title: "long", startedAt: start, endedAt: end,
            segments: [TripRepository.NewSegment(mode: "drive", startedAt: start, endedAt: end, points: track)],
            stops: []
        )
        return (repository, tripId)
    }

    /// Returning before the rows are in is the property: had `reload()` read
    /// inline, `detail` would already be set when it returned.
    func testReloadReturnsBeforeTheReadFinishes() async throws {
        let (repository, tripId) = try longTrip(points: 200_000)
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)

        let started = CFAbsoluteTimeGetCurrent()
        model.reload()
        let onMain = CFAbsoluteTimeGetCurrent() - started
        XCTAssertNil(model.detail, "the read ran on the main thread")

        await model.refresh()
        let total = CFAbsoluteTimeGetCurrent() - started
        XCTAssertEqual(model.detail?.segments.first?.points.count, 200_000)
        // Measured, not asserted: a wall-clock bound would flake on CI runners.
        print("TRIPDETAIL_RELOAD 200k: main \(Int(onMain * 1000)) ms, read \(Int(total * 1000)) ms")
    }

    /// The first reload is superseded; the second's rows are what stay.
    func testALaterReadIsNeverOverwrittenByAnEarlierOne() async throws {
        let (repository, tripId) = try longTrip(points: 50_000)
        let model = TripDetailModel(tripId: tripId, config: AppConfig.loadOrDie(), repository: repository)
        model.reload()
        try repository.setTripTitle(tripId: tripId, title: "renamed")
        await model.refresh()
        try await Task.sleep(nanoseconds: 300_000_000) // let the superseded read land
        XCTAssertEqual(model.detail?.trip.title, "renamed")
    }
}
